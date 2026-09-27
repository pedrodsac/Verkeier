import Foundation
import MapKit
import MobiliteitKit

/// App adapter for MobiliteitKit's on-device GTFS/RAPTOR journey engine.
/// It deliberately maps into the existing RoutePlan surface so route sheets,
/// map overlays and paging UI need no parallel presentation model.
struct MobiliteitRouteService: RouteService, WalkingRouteRefining {
    private nonisolated static let initialSearchHorizon: TimeInterval = 3 * 60 * 60
    let databaseURL: URL
    private let gtfsService: (any GTFSService)?
    private let engine: MobiliteitRouteEngine
    private let roadRouteProvider: any RoadRouteProviding
    private let appleMaps = MapKitRouteService()

    init(
        databaseURL: URL = MobiliteitGTFSService.installedDatabaseURL,
        gtfsService: (any GTFSService)? = nil,
        realtimeClient: MobiliteitAPIClient? = nil,
        engine: MobiliteitRouteEngine? = nil,
        walkingRouter: any WalkingRouting = StraightLineWalkingRouter(),
        roadRouteProvider: any RoadRouteProviding = MapKitRoadRouteProvider()
    ) {
        self.databaseURL = databaseURL
        self.gtfsService = gtfsService
        self.engine = engine ?? MobiliteitRouteEngine(
            walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: walkingRouter),
            realtimeClient: realtimeClient
        )
        self.roadRouteProvider = roadRouteProvider
    }

    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        let started = Date()
        let query = makeQuery(from: from, to: to, time: time, filters: filters,
                              page: page, realtimeRefreshPolicy: realtimeRefreshPolicy)
        let databaseURL = try await readyDatabaseURL()
        let feedReady = Date()
        try Task.checkCancellation()
        let router = try await engine.router(for: databaseURL)
        let snapshotReady = Date()
        try Task.checkCancellation()
        let calculation = try await localCalculation(
            using: router,
            from: from,
            to: to,
            query: query,
            page: page
        )
        let searchReady = Date()
        try Task.checkCancellation()
        let complete = await addingTransitGeometry(to: calculation)
        try Task.checkCancellation()
        if ProcessInfo.processInfo.environment["ROUTING_BENCHMARK"] == "1" {
            print("[Routing] feed=\(Int(feedReady.timeIntervalSince(started) * 1_000))ms snapshot=\(Int(snapshotReady.timeIntervalSince(feedReady) * 1_000))ms search=\(Int(searchReady.timeIntervalSince(snapshotReady) * 1_000))ms geometry=\(Int(Date().timeIntervalSince(searchReady) * 1_000))ms total=\(Int(Date().timeIntervalSince(started) * 1_000))ms")
        }
        return complete
    }

    /// Starts loading MobiliteitKit's full-feed snapshot without blocking UI
    /// work. Every request through this service joins the same engine actor.
    nonisolated func prepareForRouting() {
        let engine = engine
        Task(priority: .utility) {
            guard let databaseURL = try? await readyDatabaseURL() else { return }
            _ = try? await engine.router(for: databaseURL)
        }
    }

    /// Joins the same preparation task used by route requests. This is useful
    /// for startup coordination and integration tests without exposing router
    /// construction through `RouteService`.
    nonisolated func waitUntilPreparedForRouting() async throws {
        let databaseURL = try await readyDatabaseURL()
        _ = try await engine.router(for: databaseURL)
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        appleMaps.openInAppleMaps(from: from, to: to)
    }

    /// Replace initially approximate walking segments after a route has been
    /// shown. Consecutive walks are routed once between their outer endpoints.
    /// Failures leave the original legs in place.
    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] {
        var refinedByID = Dictionary(
            options.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for await option in refineWalkingRouteUpdates(in: options) {
            refinedByID[option.id] = option
        }
        return options.map { refinedByID[$0.id] ?? $0 }
    }

    /// Streams walking refinements as soon as each pedestrian request completes.
    /// A single walking request can be shared by multiple alternatives, so all
    /// affected options are emitted with the completed geometry applied.
    nonisolated func refineWalkingRouteUpdates(
        in options: [RouteOption]
    ) -> AsyncStream<RouteOption> {
        let requests = options.flatMap { option in
            WalkingLegSpan.spans(in: option.plan.legs)
                .filter(\.needsRouting)
                .map(\.request)
        }
        let uniqueRequests = Dictionary(
            requests.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !uniqueRequests.isEmpty else {
            return AsyncStream { continuation in continuation.finish() }
        }

        let provider = roadRouteProvider
        let maximumConcurrentRequests = 4
        let requestsToRun = Array(uniqueRequests.values)
        return AsyncStream { continuation in
            let task = Task {
                let activeURL = try? await readyDatabaseURL()
                let activeRouter: TransitRouter? = if let activeURL {
                    try? await engine.router(for: activeURL)
                } else { nil }
                var routesByLeg: [String: RoadRoute] = [:]
                var startIndex = 0

                while startIndex < requestsToRun.count {
                    guard !Task.isCancelled else { break }
                    let endIndex = min(startIndex + maximumConcurrentRequests, requestsToRun.count)
                    await withTaskGroup(of: (String, RoadRoute?).self) { group in
                        for request in requestsToRun[startIndex..<endIndex] {
                            group.addTask {
                                let route = await provider.roadRoute(
                                    from: request.origin,
                                    to: request.destination,
                                    transport: .walking
                                )
                                return (request.key, route)
                            }
                        }
                        for await (key, route) in group {
                            guard !Task.isCancelled,
                                  let route
                            else { continue }

                            if let request = uniqueRequests[key],
                               let seconds = route.expectedTravelTime,
                               seconds.isFinite, seconds >= 0,
                               route.distanceMeters.isFinite, route.distanceMeters >= 0 {
                                let walkingRequest = WalkingRequest(
                                    source: Coordinate(latitude: request.origin.latitude,
                                                       longitude: request.origin.longitude),
                                    destination: Coordinate(latitude: request.destination.latitude,
                                                            longitude: request.destination.longitude)
                                )
                                let corrected = MobiliteitKit.WalkingRoute(
                                    durationSeconds: Int(seconds.rounded()),
                                    distanceMeters: route.distanceMeters,
                                    polyline: route.coordinates.map {
                                        Coordinate(latitude: $0.latitude, longitude: $0.longitude)
                                    },
                                    evidence: route.walkingEvidence == .estimate ? .estimate : .routedPedestrian
                                )
                                await activeRouter?.correctWalkingRoute(corrected, for: walkingRequest)
                            }
                            routesByLeg[key] = route
                            for option in options where WalkingLegSpan.spans(in: option.plan.legs).contains(where: { span in
                                span.needsRouting && span.request.key == key
                            }) {
                                let refined = option.replacingWalkingRoutes(routesByLeg: routesByLeg)
                                if refined != option { continuation.yield(refined) }
                            }
                        }
                    }
                    startIndex = endIndex
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
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

    /// Adds the GTFS trip shape to transit legs. The routing engine deliberately
    /// keeps shape data out of its in-memory search snapshot, so presentation
    /// geometry is loaded only for the handful of journeys that are displayed.
    private nonisolated func addingTransitGeometry(
        to calculation: RouteCalculation
    ) async -> RouteCalculation {
        applyingTransitGeometry(await transitShapes(for: calculation), to: calculation)
    }

    private nonisolated func transitShapes(
        for calculation: RouteCalculation
    ) async -> [String: [RouteMapCoordinate]] {
        guard let gtfsService else { return [:] }
        let allOptions = calculation.options + calculation.supplementalOptions
        let tripIDs = Set(allOptions.flatMap { option in
            option.transitLegs.compactMap(\.tripId)
        })
        guard !tripIDs.isEmpty, !Task.isCancelled else { return [:] }

        let baseIDs = Dictionary(uniqueKeysWithValues: tripIDs.map { tripID in
            let base = tripID.range(of: "#frequency-").map { String(tripID[..<$0.lowerBound]) } ?? tripID
            return (tripID, base)
        })
        let shapesByID = await gtfsService.routeShapes(for: Array(tripIDs.union(baseIDs.values)))
        return baseIDs.reduce(into: [:]) { result, item in
            if let shape = shapesByID[item.key] ?? shapesByID[item.value], shape.count >= 2 {
                result[item.key] = shape
            }
        }
    }

    private nonisolated func applyingTransitGeometry(
        _ shapesByTripID: [String: [RouteMapCoordinate]],
        to calculation: RouteCalculation
    ) -> RouteCalculation {
        guard !shapesByTripID.isEmpty else { return calculation }
        return RouteCalculation(
            options: calculation.options.map { $0.replacingTransitGeometry(shapesByTripID: shapesByTripID) },
            supplementalOptions: calculation.supplementalOptions.map {
                $0.replacingTransitGeometry(shapesByTripID: shapesByTripID)
            },
            invalidatedOptionIDs: calculation.invalidatedOptionIDs,
            validationContext: calculation.validationContext,
            selectedOptionID: calculation.selectedOptionID
        )
    }

    private nonisolated func localCalculation(
        using router: TransitRouter,
        from: LocationPoint,
        to: LocationPoint,
        query: RouteQuery,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        do {
            let session = try await router.makeSession(for: query)
            let journeyPage = try await initialJourneys(using: session, page: page,
                                                        direction: query.direction)
            if ProcessInfo.processInfo.environment["ROUTING_BENCHMARK"] == "1" {
                let metrics = journeyPage.metrics
                print("[Routing] endpoints=\(metrics.endpointPreparationMilliseconds)ms live=\(metrics.realtimePreparationMilliseconds)ms RAPTOR=\(metrics.raptorSearchMilliseconds)ms transfers=\(metrics.walkingTransferMilliseconds)ms candidate=\(metrics.candidateBuildingMilliseconds)ms patterns=\(metrics.scannedPatterns) trips=\(metrics.scannedTripInstances) walkPairs=\(metrics.walkingTransferPairs) walkRequests=\(metrics.walkingRequests) walkHits=\(metrics.walkingCacheHits) journeys=\(metrics.alternativesRetained)")
            }
            guard let calculation = calculation(
                from: journeyPage,
                origin: from,
                destination: to,
                page: page,
                query: query
            ) else { throw RoutingError.noPublicTransportRoute }
            return calculation
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RoutingError {
            throw error
        } catch {
            throw RoutingError.noRouteFound
        }
    }

    private nonisolated func initialJourneys(
        using session: JourneyPlanningSession,
        page: RouteSearchPage,
        direction: RouteQueryDirection
    ) async throws -> JourneyPage {
        let count = page.resultLimit
        switch page {
        case let .earlier(boundary, _):
            return try await session.boundedPage(before: boundary, count: count)
        case let .later(boundary, _):
            return try await session.boundedPage(after: boundary, count: count)
        case let .earlierFrom(boundary, id, _):
            return try await session.boundedPage(before: boundary, beforeID: .init(id), count: count)
        case let .laterFrom(boundary, id, _):
            return try await session.boundedPage(after: boundary, afterID: .init(id), count: count)
        case .initial:
            break
        }
        if direction == .arriveBy { return try await session.expanded(count: count) }
        return try await session.initial(
            count: count,
            searchHorizon: Self.initialSearchHorizon
        )
    }

    private nonisolated func calculation(
        from journeyPage: JourneyPage,
        origin: LocationPoint,
        destination: LocationPoint,
        page: RouteSearchPage,
        query: RouteQuery
    ) -> RouteCalculation? {
        // A cancelled vehicle cannot become a usable alternative by boarding
        // it at a different stop. Filter older package results here as well.
        let options = journeyPage.journeys
            .filter { journey in
                !journey.legs.contains { leg in
                    if case let .transit(ride) = leg { return ride.status == .cancelled }
                    return false
                }
            }
            .map { option(from: $0, origin: origin, destination: destination) }
        guard !options.isEmpty else { return nil }
        return RouteCalculation(
            options: options,
            validationContext: .init(anchor: query.departureTime,
                                     arriveBy: query.direction == .arriveBy,
                                     minimumTransferSeconds: query.preferences.minimumTransferSeconds,
                                     sameStopTransferShortfallSeconds: query.preferences.sameStopTransferShortfallSeconds),
            selectedOptionID: options.first(where: { $0.id == journeyPage.recommendedJourneyID?.value })?.id
                ?? options.first?.id
        )
    }

    private nonisolated func makeQuery(
        from: LocationPoint, to: LocationPoint, time: RoutePlanningTime,
        filters: RoutePlannerFilters, page: RouteSearchPage,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy
    ) -> RouteQuery {
        let anchor: Date
        let direction: RouteQueryDirection
        switch time {
        case .leaveNow:
            anchor = .now; direction = .departAfter
        case let .departAt(value):
            anchor = value; direction = .departAfter
        case let .arriveBy(value):
            anchor = value; direction = .arriveBy
        }
        let searchAnchor: Date
        if direction == .arriveBy {
            searchAnchor = anchor
        } else {
            switch page {
            case .initial: searchAnchor = anchor
            case let .later(boundary, _), let .laterFrom(boundary, _, _): searchAnchor = boundary
            case let .earlier(boundary, _), let .earlierFrom(boundary, _, _): searchAnchor = boundary.addingTimeInterval(-86_400)
            }
        }
        return RouteQuery(origin: Self.journeyEndpoint(for: from),
                          destination: Self.journeyEndpoint(for: to),
                          departureTime: searchAnchor, direction: direction,
                          preferences: preferences(filters),
                          realtimePolicy: Self.realtimePolicy(for: realtimeRefreshPolicy, page: page))
    }

    nonisolated static func journeyEndpoint(for point: LocationPoint) -> JourneyEndpoint {
        if let transitStopID = point.transitStopID {
            return .stop(id: transitStopID)
        }
        return .coordinate(
            Coordinate(latitude: point.latitude, longitude: point.longitude),
            label: point.name
        )
    }

    private nonisolated func preferences(_ filters: RoutePlannerFilters) -> RoutingPreferences {
        let preferred: TransitModeMask? = switch filters.modePreference {
        case .any: nil
        case .bus: TransitModeMask(rawValue: 1 << 3)
        case .tram: TransitModeMask(rawValue: 1 << 0)
        case .train: TransitModeMask(rawValue: (1 << 1) | (1 << 2))
        }
        return RoutingPreferences(
            maxTransfers: 3,
            minimumTransferSeconds: filters.avoidTightTransfers ? 180 : 120,
            sameStopTransferShortfallSeconds: filters.avoidTightTransfers ? 0 : 180,
            allowedModes: .all,
            preferredMode: preferred
        )
    }

    nonisolated static func realtimePolicy(
        for policy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) -> MobiliteitKit.RealtimePolicy {
        // The HAFAS board request is capped at 100 departures per stop. Looking back
        // two hours from a later-page boundary can consume that cap before the
        // departures the rider has asked to see. Keep a short delay lookback
        // while prioritising the later page's forward prediction window.
        let isLaterPage: Bool = switch page {
        case .later, .laterFrom: true
        default: false
        }
        let configuration = RealtimeConfiguration(
            scheduledLookbackSeconds: isLaterPage ? 10 * 60 : 20 * 60
        )
        return switch policy {
        case .scheduleOnly:
            .disabled
        case .useCache:
            .bestEffort(configuration: configuration, refresh: .useCache)
        case .forceRefresh:
            .bestEffort(configuration: configuration, refresh: .forceRefresh)
        }
    }

    private nonisolated func option(
        from journey: MobiliteitKit.Journey,
        origin: LocationPoint,
        destination: LocationPoint
    ) -> RouteOption {
        var legs = journey.legs.compactMap { leg -> RoutePlan.Leg? in
            switch leg {
            case let .walk(walk):
                var result = RoutePlan.Leg(
                    id: "walk-\(walk.departure.timeIntervalSince1970)", mode: .walking,
                    transportKind: .walking, origin: point(walk.from), destination: point(walk.to),
                    departureTime: walk.departure, arrivalTime: walk.arrival,
                    distanceMeters: walk.distanceMeters,
                    mapCoordinates: walk.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    roadRoutingHint: walk.source == .provider ? .walking : .none
                )
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
                    id: "transit-\(transit.tripID)-\(transit.board.stop.id)-\(transit.alight.stop.id)",
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
                    mapCoordinates: [
                        .init(latitude: transit.board.stop.coordinate.latitude,
                              longitude: transit.board.stop.coordinate.longitude),
                        .init(latitude: transit.alight.stop.coordinate.latitude,
                              longitude: transit.alight.stop.coordinate.longitude),
                    ],
                    platform: transit.board.platform,
                    delayMinutes: departureIsRealtime ? Int((delaySeconds / 60).rounded()) : nil,
                    liveStatus: transit.status == .cancelled
                        ? .cancelled : (usesRealtime ? (delayed ? .delayed : .live) : .scheduled)
                )
                result.departureTimingSource = Self.timingSource(transit.board.timingSource)
                result.arrivalTimingSource = Self.timingSource(transit.alight.timingSource)
                result.requiredTransferSeconds = transit.requiredTransferSecondsAfterWalking
                return result
            case .inSeatContinuation:
                return nil
            }
        }

        let transitIndices = legs.indices.filter { legs[$0].transportKind == .transit }
        for (incomingIndex, outgoingIndex) in zip(transitIndices, transitIndices.dropFirst()) {
            guard legs[incomingIndex].destinationStopId == legs[outgoingIndex].originStopId,
                  let arrival = legs[incomingIndex].realtimeArrivalTime ?? legs[incomingIndex].arrivalTime,
                  let departure = legs[outgoingIndex].realtimeDepartureTime ?? legs[outgoingIndex].departureTime else { continue }
            let transferGap = departure.timeIntervalSince(arrival)
            if transferGap < 2 * 60 {
                legs[outgoingIndex].transferWarning = "Tight transfer"
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
            mapOverlay: overlay.segments.isEmpty ? nil : overlay
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

/// Owns the expensive immutable MobiliteitKit routing snapshot. A fingerprint
/// switches the cache when the GTFS service publishes a new generation file.
actor MobiliteitRouteEngine {
    private let walkingProvider: any WalkingRoutingProvider
    private let realtimeClient: MobiliteitAPIClient?
    private let suppliedRealtimeProvider: (any RealtimeRoutingProvider)?

    private struct DatabaseFingerprint: Equatable {
        let path: String
        let fileSize: UInt64
        let modificationDate: Date?
    }

    private struct Preparation {
        let id: UUID
        let fingerprint: DatabaseFingerprint?
        let task: Task<TransitRouter, Error>
    }

    private var router: TransitRouter?
    private var routerFingerprint: DatabaseFingerprint?
    private var preparation: Preparation?

    init(
        walkingProvider: any WalkingRoutingProvider = MapKitWalkingProvider(),
        realtimeClient: MobiliteitAPIClient? = nil,
        realtimeProvider: (any RealtimeRoutingProvider)? = nil
    ) {
        self.walkingProvider = walkingProvider
        self.realtimeClient = realtimeClient
        self.suppliedRealtimeProvider = realtimeProvider
    }

    func router(for databaseURL: URL) async throws -> TransitRouter {
        let fingerprint = fingerprint(for: databaseURL)
        if fingerprint == routerFingerprint, let router {
            return router
        }

        let currentPreparation: Preparation
        if let preparation, preparation.fingerprint == fingerprint {
            currentPreparation = preparation
        } else {
            let created = Preparation(
                id: UUID(),
                fingerprint: fingerprint,
                task: Task(priority: .utility) {
                    let realtimeProvider = try suppliedRealtimeProvider ?? realtimeClient.map {
                        try HafasRealtimeRoutingProvider(
                            databaseURL: databaseURL,
                            client: $0,
                            maximumConcurrentBoardRequests: 12,
                            cacheLifetime: 60,
                            requestTimeout: .seconds(4)
                        )
                    }
                    return try await TransitRouter(
                        databaseURL: databaseURL,
                        walkingProvider: walkingProvider,
                        realtimeProvider: realtimeProvider
                    )
                }
            )
            preparation = created
            currentPreparation = created
        }

        do {
            let prepared = try await currentPreparation.task.value
            guard fingerprint == self.fingerprint(for: databaseURL) else {
                if preparation?.id == currentPreparation.id {
                    preparation = nil
                }
                return try await router(for: databaseURL)
            }
            if preparation?.id == currentPreparation.id {
                router = prepared
                routerFingerprint = fingerprint
                preparation = nil
            }
            return prepared
        } catch {
            if preparation?.id == currentPreparation.id {
                preparation = nil
            }
            throw error
        }
    }

    private func fingerprint(for databaseURL: URL) -> DatabaseFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return DatabaseFingerprint(
            path: databaseURL.standardizedFileURL.path,
            fileSize: size.uint64Value,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }
}

private nonisolated struct WalkingGeometryRequest: Sendable {
    let origin: LocationPoint
    let destination: LocationPoint

    nonisolated var key: String {
        "\(origin.latitude),\(origin.longitude)|\(destination.latitude),\(destination.longitude)"
    }
}

private nonisolated struct WalkingLegSpan: Sendable {
    let range: Range<Int>
    let request: WalkingGeometryRequest
    let needsRouting: Bool

    static func spans(in legs: [RoutePlan.Leg]) -> [Self] {
        var spans: [Self] = []
        var index = 0
        while index < legs.count {
            guard legs[index].transportKind == .walking else { index += 1; continue }
            let start = index
            while index < legs.count, legs[index].transportKind == .walking { index += 1 }
            let last = legs[index - 1]
            spans.append(Self(
                range: start..<index,
                request: WalkingGeometryRequest(origin: legs[start].origin, destination: last.destination),
                needsRouting: index - start > 1 || legs[start].roadRoutingHint == .walking
            ))
        }
        return spans
    }
}

extension RouteOption {
    /// Combines independently delivered transit shapes and walking refinements
    /// without letting either update erase the other one's legs.
    nonisolated func replacingLegs(
        of kind: RouteLegTransportKind,
        from updated: RouteOption,
        preserveUpdatedTotals: Bool = false
    ) -> RouteOption {
        guard id == updated.id else { return self }
        if kind == .walking {
            // A direct pedestrian route can replace several walking legs with
            // one. Use its leg sequence, retaining any newer transit shapes.
            let currentTransitByID = Dictionary(
                plan.legs.filter { $0.transportKind == .transit }.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let legs = updated.plan.legs.map { leg in
                leg.transportKind == .transit ? currentTransitByID[leg.id] ?? leg : leg
            }
            return replacingLegs(
                legs,
                expectedTravelTime: preserveUpdatedTotals ? updated.plan.expectedTravelTime : nil,
                distanceMeters: preserveUpdatedTotals ? updated.plan.distanceMeters : nil
            )
        }
        let updatedByID = Dictionary(
            updated.plan.legs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let legs = plan.legs.map { leg in
            guard leg.transportKind == kind,
                  let replacement = updatedByID[leg.id],
                  replacement.transportKind == kind
            else { return leg }
            return replacement
        }
        return replacingLegs(
            legs,
            expectedTravelTime: preserveUpdatedTotals ? updated.plan.expectedTravelTime : nil,
            distanceMeters: preserveUpdatedTotals ? updated.plan.distanceMeters : nil
        )
    }

    nonisolated func replacingTransitGeometry(
        shapesByTripID: [String: [RouteMapCoordinate]]
    ) -> RouteOption {
        let legs = plan.legs.map { leg -> RoutePlan.Leg in
            guard leg.transportKind == .transit,
                  let tripID = leg.tripId,
                  let shape = shapesByTripID[tripID]
            else { return leg }
            return leg.replacingMapCoordinates(
                Self.segment(
                    of: shape,
                    from: RouteMapCoordinate(leg.origin),
                    to: RouteMapCoordinate(leg.destination)
                )
            )
        }
        return replacingLegs(legs)
    }

    nonisolated func replacingWalkingRoutes(routesByLeg: [String: RoadRoute]) -> RouteOption {
        var legs: [RoutePlan.Leg] = []
        let original = plan.legs
        let spans = WalkingLegSpan.spans(in: original)
        func usableDirectRoute(for span: WalkingLegSpan) -> RoadRoute? {
            guard span.range.count > 1,
                  let route = routesByLeg[span.request.key],
                  let seconds = route.expectedTravelTime,
                  seconds.isFinite, seconds >= 0,
                  route.distanceMeters.isFinite, route.distanceMeters >= 0,
                  route.walkingEvidence == .routedPedestrian,
                  route.coordinates.count >= 2 else { return nil }
            return route
        }
        guard spans.contains(where: { span in
            usableDirectRoute(for: span) != nil
                || (span.range.count == 1 && span.needsRouting
                    && routesByLeg[span.request.key] != nil)
        }) else { return self }

        var cursor = 0
        for span in spans {
            legs.append(contentsOf: original[cursor..<span.range.lowerBound])
            let source = original[span.range.lowerBound]
            let end = original[span.range.upperBound - 1]
            if let directRoute = usableDirectRoute(for: span) {
                var merged = RoutePlan.Leg(
                    id: source.id, mode: .walking, instruction: source.instruction,
                    transportKind: .walking, origin: source.origin, destination: end.destination,
                    departureTime: source.departureTime, arrivalTime: end.arrivalTime,
                    distanceMeters: directRoute.distanceMeters,
                    mapCoordinates: directRoute.coordinates, roadRoutingHint: .walking
                )
                merged.departureTimingSource = source.departureTimingSource
                merged.arrivalTimingSource = end.arrivalTimingSource
                merged.walkingEvidence = .routedPedestrian
                legs.append(merged)
            } else {
                legs.append(contentsOf: original[span.range])
            }
            cursor = span.range.upperBound
        }
        legs.append(contentsOf: original[cursor...])

        func route(for leg: RoutePlan.Leg) -> RoadRoute? {
            guard leg.roadRoutingHint == .walking else { return nil }
            return routesByLeg[WalkingGeometryRequest(origin: leg.origin, destination: leg.destination).key]
        }
        func duration(_ leg: RoutePlan.Leg) -> TimeInterval {
            if let value = route(for: leg)?.expectedTravelTime, value.isFinite, value >= 0 {
                return value
            }
            return max(0, (leg.arrivalTime ?? .distantPast)
                .timeIntervalSince(leg.departureTime ?? .distantPast))
        }
        func replace(_ leg: RoutePlan.Leg, from departure: Date, through arrival: Date) -> RoutePlan.Leg {
            let geometry = route(for: leg)
            var updated = RoutePlan.Leg(
                id: leg.id, mode: leg.mode, instruction: leg.instruction,
                transportKind: leg.transportKind, routeName: leg.routeName,
                headsign: leg.headsign, routeId: leg.routeId, tripId: leg.tripId,
                originStopId: leg.originStopId, destinationStopId: leg.destinationStopId,
                stopCount: leg.stopCount, origin: leg.origin, destination: leg.destination,
                departureTime: departure, arrivalTime: arrival,
                scheduledDepartureTime: departure, scheduledArrivalTime: arrival,
                realtimeDepartureTime: leg.realtimeDepartureTime,
                realtimeArrivalTime: leg.realtimeArrivalTime,
                distanceMeters: geometry?.distanceMeters ?? leg.distanceMeters,
                mapCoordinates: geometry?.coordinates ?? leg.mapCoordinates,
                roadRoutingHint: leg.roadRoutingHint, platform: leg.platform,
                delayMinutes: leg.delayMinutes, liveStatus: leg.liveStatus,
                transferWarning: leg.transferWarning,
                bikeShareDetails: leg.bikeShareDetails
            )
            updated.departureTimingSource = leg.departureTimingSource
            updated.arrivalTimingSource = leg.arrivalTimingSource
            updated.requiredTransferSeconds = leg.requiredTransferSeconds
            updated.walkingEvidence = geometry?.walkingEvidence ?? leg.walkingEvidence
            return updated
        }

        var index = 0
        while index < legs.count {
            guard legs[index].transportKind == .walking else { index += 1; continue }
            let start = index
            while index < legs.count && legs[index].transportKind == .walking { index += 1 }
            let end = index
            guard (start..<end).contains(where: { route(for: legs[$0]) != nil }) else { continue }

            if start == 0 && end < legs.count && legs[end].transportKind == .transit,
               let boarding = legs[end].realtimeDepartureTime ?? legs[end].departureTime {
                var cursor = boarding
                for position in (start..<end).reversed() {
                    let departure = cursor.addingTimeInterval(-duration(legs[position]))
                    legs[position] = replace(legs[position], from: departure, through: cursor)
                    cursor = departure
                }
            } else if let firstDeparture = start == 0
                ? legs[start].departureTime
                : (legs[start - 1].realtimeArrivalTime ?? legs[start - 1].arrivalTime) {
                var cursor = firstDeparture
                for position in start..<end {
                    let arrival = cursor.addingTimeInterval(duration(legs[position]))
                    legs[position] = replace(legs[position], from: cursor, through: arrival)
                    cursor = arrival
                }
            }
        }
        let first = legs.first?.realtimeDepartureTime ?? legs.first?.departureTime
        let last = legs.last?.realtimeArrivalTime ?? legs.last?.arrivalTime
        let elapsed = first.flatMap { departure in last.map { max(0, $0.timeIntervalSince(departure)) } }
        let distance = legs.filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters).reduce(0, +)
        return replacingLegs(legs, expectedTravelTime: elapsed,
                             distanceMeters: distance)
    }

    nonisolated func replacingLegs(
        _ legs: [RoutePlan.Leg],
        expectedTravelTime: TimeInterval? = nil,
        distanceMeters: Double? = nil
    ) -> RouteOption {
        let updatedPlan = RoutePlan(
            id: plan.id,
            origin: plan.origin,
            destination: plan.destination,
            expectedTravelTime: expectedTravelTime ?? plan.expectedTravelTime,
            distanceMeters: distanceMeters ?? plan.distanceMeters,
            legs: legs,
            dataSource: plan.dataSource
        )
        let overlay = RouteMapOverlay(segments: legs.compactMap { leg in
            guard leg.mapCoordinates.count >= 2 else { return nil }
            return RouteMapSegment(
                id: leg.id,
                mode: leg.mode,
                routeName: leg.routeName,
                routeId: leg.routeId,
                coordinates: leg.mapCoordinates
            )
        })
        return RouteOption(id: id, plan: updatedPlan, mapOverlay: overlay.isEmpty ? nil : overlay,
                           feasibility: feasibility)
    }

    /// Keeps only the ridden portion of a full-trip GTFS shape. Searching from
    /// the boarding match onward also preserves the direction when a shape
    /// loops near the same stop more than once.
    nonisolated static func segment(
        of shape: [RouteMapCoordinate],
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate
    ) -> [RouteMapCoordinate] {
        guard shape.count >= 2 else { return shape }
        let start = shape.indices.min { distanceSquared(shape[$0], origin) < distanceSquared(shape[$1], origin) }
            ?? shape.startIndex
        let remaining = start..<shape.endIndex
        let end = remaining.min { distanceSquared(shape[$0], destination) < distanceSquared(shape[$1], destination) }
            ?? shape.index(before: shape.endIndex)
        guard end > start else {
            // Some feeds reuse a shape in reverse. Prefer a drawable fallback
            // over hiding the transit leg entirely.
            return [origin, destination]
        }
        var result = Array(shape[start...end])
        result[0] = origin
        result[result.index(before: result.endIndex)] = destination
        return result
    }

    nonisolated static func distanceSquared(
        _ lhs: RouteMapCoordinate,
        _ rhs: RouteMapCoordinate
    ) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = (lhs.longitude - rhs.longitude)
            * cos((lhs.latitude + rhs.latitude) * .pi / 360)
        return latitude * latitude + longitude * longitude
    }
}

private extension RoutePlan.Leg {
    nonisolated func replacingMapCoordinates(_ coordinates: [RouteMapCoordinate]) -> Self {
        var replacement = Self(
            id: id, mode: mode, instruction: instruction, transportKind: transportKind,
            routeName: routeName, headsign: headsign, routeId: routeId, tripId: tripId,
            originStopId: originStopId, destinationStopId: destinationStopId, stopCount: stopCount,
            origin: origin, destination: destination, departureTime: departureTime, arrivalTime: arrivalTime,
            scheduledDepartureTime: scheduledDepartureTime, scheduledArrivalTime: scheduledArrivalTime,
            realtimeDepartureTime: realtimeDepartureTime, realtimeArrivalTime: realtimeArrivalTime,
            distanceMeters: distanceMeters, mapCoordinates: coordinates, roadRoutingHint: roadRoutingHint,
            platform: platform, delayMinutes: delayMinutes, liveStatus: liveStatus,
            transferWarning: transferWarning, bikeShareDetails: bikeShareDetails
        )
        replacement.departureTimingSource = departureTimingSource
        replacement.arrivalTimingSource = arrivalTimingSource
        replacement.requiredTransferSeconds = requiredTransferSeconds
        replacement.walkingEvidence = walkingEvidence
        return replacement
    }
}

private struct MapKitWalkingProvider: WalkingRoutingProvider {
    /// The router asks this provider for walking access to its 24 closest stops
    /// at *each* endpoint. Asking MapKit for every candidate serially made one
    /// journey search issue up to 49 directions requests (24 + 24 + direct),
    /// which is slow enough to hit Apple's request throttling before the
    /// timetable search even begins.
    ///
    /// Use a conservative, local approximation for the candidate search. The
    /// journey engine only needs an access-time estimate at this stage; a
    /// straight-line geometry is sufficient for the route overlay and avoids
    /// making routing availability depend on dozens of network calls.
    private static let walkingSpeedMetersPerSecond = 1.25
    private static let pathStretchFactor = 1.2
    private static let maximumCandidateDistanceMeters = 1_500.0

    func estimate(_ request: WalkingRequest) async throws -> WalkingEstimate {
        let estimate = approximation(for: request)
        guard estimate.distanceMeters <= Self.maximumCandidateDistanceMeters else {
            throw LocalWalkingError.outsideCandidateRadius
        }
        return .init(
            durationSeconds: estimate.durationSeconds,
            distanceMeters: estimate.distanceMeters
        )
    }

    func route(_ request: WalkingRequest) async throws -> WalkingRoute {
        let estimate = approximation(for: request)
        guard estimate.distanceMeters <= Self.maximumCandidateDistanceMeters else {
            throw LocalWalkingError.outsideCandidateRadius
        }
        return .init(
            durationSeconds: estimate.durationSeconds,
            distanceMeters: estimate.distanceMeters,
            polyline: [request.source, request.destination],
            evidence: .estimate
        )
    }

    private func approximation(for request: WalkingRequest) -> (durationSeconds: Int, distanceMeters: Double) {
        let directDistance = CLLocation(
            latitude: request.source.latitude,
            longitude: request.source.longitude
        ).distance(from: CLLocation(
            latitude: request.destination.latitude,
            longitude: request.destination.longitude
        ))
        let distanceMeters = directDistance * Self.pathStretchFactor
        return (
            durationSeconds: max(1, Int((distanceMeters / Self.walkingSpeedMetersPerSecond).rounded())),
            distanceMeters: distanceMeters
        )
    }

    private enum LocalWalkingError: Error {
        case outsideCandidateRadius
    }
}
