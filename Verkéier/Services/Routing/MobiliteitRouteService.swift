import Foundation
import MapKit
import MobiliteitKit

/// Presentation adapter. Transit policy and request state belong to MobiliteitKit.
struct MobiliteitRouteService: RouteService, WalkingRouteRefining {
    let databaseURL: URL
    private let gtfsService: (any GTFSService)?
    let engine: JourneyPlanner
    let sessions: AppJourneySessionStore
    private let walkingRouter: any WalkingRouting
    let roadRouteProvider: any RoadRouteProviding
    private let graphPreparation: Task<Void, Never>?
    private let appleMaps = MapKitRouteService()

    init(databaseURL: URL = MobiliteitGTFSService.installedDatabaseURL,
         gtfsService: (any GTFSService)? = nil, realtimeClient: MobiliteitAPIClient? = nil,
         engine: JourneyPlanner? = nil,
         walkingRouter: any WalkingRouting = UnavailableWalkingRouter(),
         roadRouteProvider: (any RoadRouteProviding)? = nil,
         graphPreparation: Task<Void, Never>? = nil) {
        self.databaseURL = databaseURL; self.gtfsService = gtfsService
        let planner = engine ?? JourneyPlanner(
            walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: walkingRouter),
            realtimeClient: realtimeClient)
        self.engine = planner; self.sessions = AppJourneySessionStore(planner: planner)
        self.walkingRouter = walkingRouter
        self.roadRouteProvider = roadRouteProvider ?? LocalFirstRoadRouteProvider(walkingRouter: walkingRouter)
        self.graphPreparation = graphPreparation
    }

    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint,
        time: RoutePlanningTime, filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        let started = ContinuousClock.now
        let databaseURL = try await readyDatabaseURL()
        let readiness = RoutingDiagnostics.elapsed(since: started)
        let graphStarted = ContinuousClock.now
        await graphPreparation?.value
        try Task.checkCancellation()
        do {
            try await walkingRouter.checkAvailability()
            let graphMilliseconds = RoutingDiagnostics.elapsed(since: graphStarted)
            let result = try await sessions.calculate(databaseURL: databaseURL,
                request: .init(origin: Self.journeyEndpoint(for: from),
                    destination: Self.journeyEndpoint(for: to), time: time.packageTime,
                    preferences: filters.packagePreferences, realtimeAcquisitionBudgetMilliseconds: 2_500,
                    realtimeMaximumConcurrentBoardRequests: 16, realtimeSearchWorkBudgetMilliseconds: 4_100,
                    pagingPolicy: .adjacentTimeWindows),
                page: page.packagePage, refresh: realtimeRefreshPolicy.packagePolicy)
            var calculation = calculation(from: result, origin: from, destination: to)
            calculation.diagnostics?.milliseconds[.timetableReadiness] = readiness
            calculation.diagnostics?.milliseconds[.graphPreparation] = graphMilliseconds
            calculation.diagnostics?.totalMilliseconds = RoutingDiagnostics.elapsed(since: started)
            return calculation
        } catch is CancellationError { throw CancellationError() }
        catch JourneyPlanningError.supersededRequest { throw CancellationError() }
        catch WalkingRoutingError.datasetUnavailable { throw RoutingError.walkingUnavailable }
        catch JourneyPlanningError.noRouteFound { throw RoutingError.noPublicTransportRoute }
        catch { throw RoutingError.noRouteFound }
    }

    nonisolated func prepareForRouting() {
        Task(priority: .utility) { _ = try? await engine.router(for: readyDatabaseURL()) }
    }
    nonisolated func waitUntilPreparedForRouting() async throws {
        _ = try await engine.router(for: readyDatabaseURL())
    }
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        appleMaps.openInAppleMaps(from: from, to: to)
    }

    nonisolated static func journeyEndpoint(for point: LocationPoint) -> JourneyEndpoint {
        if let stopID = point.transitStopID { return .stop(id: stopID) }
        return .coordinate(.init(latitude: point.latitude, longitude: point.longitude), label: point.name)
    }

    nonisolated func calculation(from result: JourneyPlanningResult,
        origin: LocationPoint, destination: LocationPoint) -> RouteCalculation {
        let started = ContinuousClock.now
        var calculation = RouteCalculation(options: result.journeys.map {
            option(from: $0, origin: origin, destination: destination, result: result)
        }, selectedOptionID: result.recommendedJourneyID?.value)
        calculation.invalidatedOptionIDs = Set(result.invalidatedIDs.map(\.value))
        calculation.validationContext = result.validationContext
        calculation.browsingWindow = result.browsingWindow
        calculation.isAuthoritativeSnapshot = true
        calculation.canLoadEarlier = result.hasEarlier
        calculation.canLoadLater = result.hasLater
        calculation.diagnostics = result.diagnostics
        calculation.diagnostics?.record(.adapterMapping, since: started)
        return calculation
    }

    private nonisolated func readyDatabaseURL() async throws -> URL {
        var activeDatabaseURL = databaseURL
        if let service = gtfsService as? MobiliteitGTFSService {
            if let installedDatabaseURL = await service.routingDatabaseURL() {
                activeDatabaseURL = installedDatabaseURL
            } else {
                let status = await service.refreshIfNeeded(force: false)
                guard status.isReady,
                      let installedDatabaseURL = await service.routingDatabaseURL()
                else { throw RoutingError.timetableUnavailable }
                activeDatabaseURL = installedDatabaseURL
            }
        } else if let gtfsService {
            let status = await gtfsService.refreshIfNeeded(force: false)
            guard status.isReady else { throw RoutingError.timetableUnavailable }
        }
        guard FileManager.default.fileExists(atPath: activeDatabaseURL.path) else {
            throw RoutingError.timetableUnavailable
        }
        return activeDatabaseURL
    }

    private nonisolated func option(
        from journey: MobiliteitKit.Journey,
        origin: LocationPoint,
        destination: LocationPoint,
        result planningResult: JourneyPlanningResult
    ) -> RouteOption {
        let legs = journey.legs.enumerated().compactMap { nativeIndex, leg -> RoutePlan.Leg? in
            switch leg {
            case let .walk(walk):
                guard walk.duration > 0 || walk.from.coordinate != walk.to.coordinate else { return nil }
                var result = RoutePlan.Leg(
                    id: "walk-\(journey.id.value)-\(nativeIndex)", mode: .walking,
                    transportKind: .walking, origin: point(walk.from), destination: point(walk.to),
                    departureTime: walk.departure, arrivalTime: walk.arrival,
                    distanceMeters: walk.distanceMeters,
                    mapCoordinates: walk.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    roadRoutingHint: walk.source == .provider ? .walking : .none
                )
                result.nativeWalkingRange = walk.nativeRange ?? (nativeIndex..<(nativeIndex + 1))
                result.walkingEvidence = walk.evidence == .routedPedestrian
                    ? .routedPedestrian : .estimate
                return result
            case let .transit(transit):
                let departureIsRealtime = transit.board.timingSource != .scheduled
                let arrivalIsRealtime = transit.alight.timingSource != .scheduled
                let usesRealtime = departureIsRealtime || arrivalIsRealtime
                let delaySeconds = transit.effectiveDeparture.timeIntervalSince(
                    transit.scheduledDeparture
                )
                let delayed = usesRealtime && delaySeconds > 0
                var result = RoutePlan.Leg(
                    id: "transit-\(transit.instance?.stableKey ?? transit.tripID)-\(transit.boardSequence ?? nativeIndex)-\(transit.alightSequence ?? nativeIndex)",
                    mode: Self.mode(forGTFSRouteType: transit.route.type), transportKind: .transit,
                    routeName: transit.route.shortName ?? transit.route.longName,
                    headsign: transit.headsign, routeId: transit.route.id, tripId: transit.tripID,
                    originStopId: transit.board.stop.id, destinationStopId: transit.alight.stop.id,
                    stopCount: transit.intermediateStops.count + 1,
                    origin: point(transit.board.stop), destination: point(transit.alight.stop),
                    departureTime: transit.effectiveDeparture, arrivalTime: transit.effectiveArrival,
                    scheduledDepartureTime: transit.scheduledDeparture, scheduledArrivalTime: transit.scheduledArrival,
                    realtimeDepartureTime: departureIsRealtime ? transit.effectiveDeparture : nil,
                    realtimeArrivalTime: arrivalIsRealtime ? transit.effectiveArrival : nil,
                    mapCoordinates: transit.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    platform: transit.board.platform,
                    delayMinutes: departureIsRealtime ? Int((delaySeconds / 60).rounded()) : nil,
                    liveStatus: transit.status == .cancelled
                        ? .cancelled : (usesRealtime ? (delayed ? .delayed : .live) : .scheduled)
                )
                if let risk = planningResult.transferRisks[journey.id]?[nativeIndex] {
                    result.transferWarning = risk == .tight ? "Tight transfer" : "Connection miss"
                }
                result.departureTimingSource = Self.timingSource(transit.board.timingSource)
                result.arrivalTimingSource = Self.timingSource(transit.alight.timingSource)
                result.requiredTransferSeconds = transit.requiredTransferSecondsAfterWalking
                result.requiredTotalTransferSeconds = transit.requiredTotalTransferSeconds
                result.transitInstanceKey = transit.instance?.stableKey
                result.boardingStopSequence = transit.boardSequence
                result.alightingStopSequence = transit.alightSequence
                if nativeIndex > 0, case let .inSeatContinuation(link) = journey.legs[nativeIndex - 1] {
                    result.continuesInSeatFromTripID = link.fromTripID
                    result.transferWarning = nil
                }
                return result
            case .inSeatContinuation:
                return nil
            }
        }

        let plan = RoutePlan(id: journey.id.value, origin: origin, destination: destination,
                             expectedTravelTime: journey.duration,
                             distanceMeters: journey.walkingDistance,
                             legs: legs, dataSource: .local)
        let overlay = RouteMapOverlay(segments: legs.compactMap { leg in
            guard leg.mapCoordinates.count >= 2 else { return nil }
            return RouteMapSegment(id: leg.id, mode: leg.mode, routeName: leg.routeName, routeId: leg.routeId, coordinates: leg.mapCoordinates)
        })
        return RouteOption(
            id: journey.id.value, plan: plan,
            mapOverlay: overlay.segments.isEmpty ? nil : overlay,
            feasibility: planningResult.feasibility[journey.id],
            journeySummary: journey.summary,
            statusEvidence: journey.statusEvidence,
            validationContext: planningResult.validationContexts[journey.id] ?? planningResult.validationContext,
            refinementToken: planningResult.refinementTokens[journey.id]
        )
    }

    private nonisolated func point(_ source: MobiliteitKit.TransitStop) -> LocationPoint {
        .init(
            id: source.id,
            name: source.name,
            latitude: source.coordinate.latitude,
            longitude: source.coordinate.longitude,
            transitStopID: source.id
        )
    }

    private nonisolated func point(_ source: JourneyLocation) -> LocationPoint {
        .init(
            id: source.stop?.id,
            name: source.label ?? source.stop?.name,
            latitude: source.coordinate.latitude,
            longitude: source.coordinate.longitude,
            transitStopID: source.stop?.id
        )
    }
    /// Maps GTFS route types into the app's smaller presentation taxonomy.
    /// Type `0` is the standard GTFS tram value; Luxembourg's feed can also
    /// use the extended tram range (`900...999`).
    nonisolated static func mode(forGTFSRouteType value: Int) -> TransportMode {
        switch value {
        case 0, 900...999: .tram
        case 1, 2: .train
        case 3, 700...799: .bus
        case 7: .funicular
        default: .unknown
        }
    }

    private nonisolated static func timingSource(
        _ source: RealtimeTimingSource
    ) -> RouteTimingSource {
        switch source {
        case .scheduled: .scheduled
        case .reported: .observed
        case .estimated: .estimated
        }
    }
}
