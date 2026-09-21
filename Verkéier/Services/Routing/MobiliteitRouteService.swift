import Foundation
import MapKit
import MobiliteitKit

/// App adapter for MobiliteitKit's on-device GTFS/RAPTOR journey engine.
/// It deliberately maps into the existing RoutePlan surface so route sheets,
/// map overlays, accessibility, and paging UI need no parallel presentation
/// model.
struct MobiliteitRouteService: RouteService, WalkingRouteRefining {
    private nonisolated static let previewSearchHorizon: TimeInterval = 30 * 60
    let databaseURL: URL
    private let gtfsService: (any GTFSService)?
    private let liveTransitService: (any LiveTransitService)?
    private let engine: MobiliteitRouteEngine
    private let roadRouteProvider: any RoadRouteProviding
    private let appleMaps = MapKitRouteService()

    init(
        databaseURL: URL = MobiliteitGTFSService.installedDatabaseURL,
        gtfsService: (any GTFSService)? = nil,
        liveTransitService: (any LiveTransitService)? = nil,
        engine: MobiliteitRouteEngine? = nil,
        walkingRouter: any WalkingRouting = StraightLineWalkingRouter(),
        roadRouteProvider: any RoadRouteProviding = MapKitRoadRouteProvider()
    ) {
        self.databaseURL = databaseURL
        self.gtfsService = gtfsService
        self.liveTransitService = liveTransitService
        self.engine = engine ?? MobiliteitRouteEngine(
            walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: walkingRouter)
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
        let anchor: Date = switch time {
        case .leaveNow: .now
        case let .departAt(value): value
        // The on-device engine is leave-after. For arrive-by the app starts an
        // earlier profile window; users can refine with Earlier from there.
        case let .arriveBy(value): value.addingTimeInterval(-2 * 60 * 60)
        }
        let searchAnchor: Date = switch page {
        case .initial: anchor
        case let .later(boundary, _): boundary.addingTimeInterval(1)
        case let .earlier(boundary, _): boundary.addingTimeInterval(-2 * 60 * 60)
        }
        let databaseURL = try await readyDatabaseURL()
        let router = try await engine.router(for: databaseURL)
        let calculation = try await localCalculation(
            using: router,
            from: from,
            to: to,
            searchAnchor: searchAnchor,
            filters: filters,
            page: page
        )
        return await fullyEnrichedCalculation(to: calculation, policy: realtimeRefreshPolicy)
    }

    nonisolated func routeCalculationUpdates(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        guard case .initial = page else {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        continuation.yield(try await calculateRoute(
                            from: from,
                            to: to,
                            time: time,
                            filters: filters,
                            realtimeRefreshPolicy: realtimeRefreshPolicy,
                            page: page
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task(priority: .userInitiated) {
                do {
                    let anchor: Date = switch time {
                    case .leaveNow: .now
                    case let .departAt(value): value
                    case let .arriveBy(value): value.addingTimeInterval(-2 * 60 * 60)
                    }
                    let databaseURL = try await readyDatabaseURL()
                    let router = try await engine.router(for: databaseURL)
                    let session = try await router.makeSession(for: RouteQuery(
                        origin: Self.journeyEndpoint(for: from),
                        destination: Self.journeyEndpoint(for: to),
                        departureTime: anchor,
                        preferences: preferences(filters)
                    ))

                    var published = false
                    let preview = try await session.initial(
                        count: max(page.resultLimit, 5),
                        searchHorizon: Self.previewSearchHorizon
                    )
                    if let previewCalculation = calculation(
                        from: preview,
                        origin: from,
                        destination: to,
                        page: page,
                        stage: .preview
                    ) {
                        published = true
                        continuation.yield(previewCalculation)
                    }

                    try Task.checkCancellation()
                    let expanded = try await session.expanded(count: max(page.resultLimit, 5))
                    if let finalCalculation = calculation(
                        from: expanded,
                        origin: from,
                        destination: to,
                        page: page,
                        stage: .final
                    ) {
                        published = true
                        // Publish the complete scheduled profile immediately.
                        // Geometry and live boards are independent and run in
                        // parallel from this point.
                        continuation.yield(finalCalculation)
                        async let shapes = transitShapes(for: finalCalculation)
                        var latest = finalCalculation

                        for await enriched in realtimeDisplayUpdates(
                            to: finalCalculation,
                            policy: realtimeRefreshPolicy
                        ) {
                            latest = enriched
                            continuation.yield(enriched)
                        }
                        let resolvedShapes = await shapes
                        if !resolvedShapes.isEmpty {
                            continuation.yield(applyingTransitGeometry(resolvedShapes, to: latest))
                        }
                    }
                    if published {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: RoutingError.noPublicTransportRoute)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Starts loading MobiliteitKit's full-feed snapshot without blocking UI
    /// work. Every request through this service joins the same engine actor.
    nonisolated func prepareForRouting() {
        let fallbackDatabaseURL = databaseURL
        let engine = engine
        let gtfsService = gtfsService
        Task(priority: .utility) {
            var databaseURL = fallbackDatabaseURL
            if let gtfsService {
                let refreshed = await gtfsService.refreshIfNeeded(force: false)
                guard refreshed.isReady else { return }
                if let service = gtfsService as? MobiliteitGTFSService,
                   let activeDatabaseURL = await service.routingDatabaseURL() {
                    databaseURL = activeDatabaseURL
                }
            }
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
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

    /// Replace the initially approximate walking segments after a route has
    /// already been shown. MapKit supplies both pedestrian geometry and time.
    /// Failures leave the quick local estimate in place.
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

    /// Streams walking refinements as soon as each MapKit request completes.
    /// A single walking request can be shared by multiple alternatives, so all
    /// affected options are emitted with the completed geometry applied.
    nonisolated func refineWalkingRouteUpdates(
        in options: [RouteOption]
    ) -> AsyncStream<RouteOption> {
        let requests = options.flatMap { option in
            option.plan.legs.compactMap { leg -> WalkingGeometryRequest? in
                guard leg.transportKind == .walking,
                      leg.roadRoutingHint == .walking else { return nil }
                return .init(origin: leg.origin, destination: leg.destination)
            }
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

                            routesByLeg[key] = route
                            for option in options where option.plan.legs.contains(where: { leg in
                                leg.transportKind == .walking
                                    && leg.roadRoutingHint == .walking
                                    && WalkingGeometryRequest(
                                        origin: leg.origin,
                                        destination: leg.destination
                                    ).key == key
                            }) {
                                continuation.yield(
                                    option.replacingWalkingRoutes(routesByLeg: routesByLeg)
                                )
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
        if let gtfsService {
            let status = await gtfsService.refreshIfNeeded(force: false)
            guard status.isReady else { throw RoutingError.timetableUnavailable }
            if let service = gtfsService as? MobiliteitGTFSService,
               let installedDatabaseURL = await service.routingDatabaseURL() {
                activeDatabaseURL = installedDatabaseURL
            }
        }
        guard FileManager.default.fileExists(atPath: activeDatabaseURL.path) else {
            throw RoutingError.timetableUnavailable
        }
        return activeDatabaseURL
    }

    /// Route choice is always produced by the static GTFS/RAPTOR search above.
    /// Live boards are joined afterwards and only annotate the chosen timetable
    /// legs for presentation (updated time, delay, cancellation and platform).
    private nonisolated func addingRealtimeDisplayData(
        to calculation: RouteCalculation,
        policy: RouteRealtimeRefreshPolicy
    ) async -> RouteCalculation {
        guard policy != .scheduleOnly,
              let liveTransitService
        else { return calculation }

        let enricher = RouteRealtimeEnricher(liveTransitService: liveTransitService)
        let optionCount = calculation.options.count
        let enriched = await enricher.enrich(calculation.options + calculation.supplementalOptions)
        return RouteCalculation(
            options: Array(enriched.prefix(optionCount)),
            supplementalOptions: Array(enriched.dropFirst(optionCount)),
            invalidatedOptionIDs: calculation.invalidatedOptionIDs,
            stage: calculation.stage,
            selectedOptionID: calculation.selectedOptionID
        )
    }

    /// Streams partial live overlays so one slow departure board cannot delay
    /// every route card. Static route choice and ordering remain untouched.
    private nonisolated func realtimeDisplayUpdates(
        to calculation: RouteCalculation,
        policy: RouteRealtimeRefreshPolicy
    ) -> AsyncStream<RouteCalculation> {
        guard policy != .scheduleOnly,
              let liveTransitService
        else {
            return AsyncStream { continuation in continuation.finish() }
        }

        let optionCount = calculation.options.count
        let allOptions = calculation.options + calculation.supplementalOptions
        let enricher = RouteRealtimeEnricher(liveTransitService: liveTransitService)
        return AsyncStream { continuation in
            let task = Task {
                for await enriched in enricher.updates(for: allOptions) {
                    continuation.yield(RouteCalculation(
                        options: Array(enriched.prefix(optionCount)),
                        supplementalOptions: Array(enriched.dropFirst(optionCount)),
                        invalidatedOptionIDs: calculation.invalidatedOptionIDs,
                        stage: calculation.stage,
                        selectedOptionID: calculation.selectedOptionID
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Adds the GTFS trip shape to transit legs. The routing engine deliberately
    /// keeps shape data out of its in-memory search snapshot, so presentation
    /// geometry is loaded only for the handful of journeys that are displayed.
    private nonisolated func addingTransitGeometry(
        to calculation: RouteCalculation
    ) async -> RouteCalculation {
        applyingTransitGeometry(await transitShapes(for: calculation), to: calculation)
    }

    private nonisolated func fullyEnrichedCalculation(
        to calculation: RouteCalculation,
        policy: RouteRealtimeRefreshPolicy
    ) async -> RouteCalculation {
        async let shapesTask = transitShapes(for: calculation)
        async let realtimeTask = addingRealtimeDisplayData(to: calculation, policy: policy)
        let (shapes, realtime) = await (shapesTask, realtimeTask)
        return applyingTransitGeometry(shapes, to: realtime)
    }

    private nonisolated func transitShapes(
        for calculation: RouteCalculation
    ) async -> [String: [RouteMapCoordinate]] {
        guard let gtfsService else { return [:] }
        let allOptions = calculation.options + calculation.supplementalOptions
        let tripIDs = Set(allOptions.flatMap { option in
            option.transitLegs.compactMap(\.tripId)
        })
        guard !tripIDs.isEmpty else { return [:] }

        let shapesByTripID = await withTaskGroup(
            of: (String, [RouteMapCoordinate]).self,
            returning: [String: [RouteMapCoordinate]].self
        ) { group in
            for tripID in tripIDs {
                group.addTask {
                    var shape = await gtfsService.routeShape(for: tripID)
                    if shape.isEmpty,
                       let frequencySuffix = tripID.range(of: "#frequency-") {
                        shape = await gtfsService.routeShape(
                            for: String(tripID[..<frequencySuffix.lowerBound])
                        )
                    }
                    return (tripID, shape)
                }
            }
            var shapes: [String: [RouteMapCoordinate]] = [:]
            for await (tripID, shape) in group where shape.count >= 2 {
                shapes[tripID] = shape
            }
            return shapes
        }
        return shapesByTripID
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
            stage: calculation.stage,
            selectedOptionID: calculation.selectedOptionID
        )
    }

    private nonisolated func localCalculation(
        using router: TransitRouter,
        from: LocationPoint,
        to: LocationPoint,
        searchAnchor: Date,
        filters: RoutePlannerFilters,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        do {
            let session = try await router.makeSession(for: RouteQuery(
                origin: Self.journeyEndpoint(for: from),
                destination: Self.journeyEndpoint(for: to),
                departureTime: searchAnchor,
                preferences: preferences(filters)
            ))
            let journeyPage = try await session.initial(count: max(page.resultLimit, 5))
            guard let calculation = calculation(
                from: journeyPage,
                origin: from,
                destination: to,
                page: page
            ) else { throw RoutingError.noPublicTransportRoute }
            return calculation
        } catch let error as RoutingError {
            throw error
        } catch {
            throw RoutingError.noRouteFound
        }
    }

    private nonisolated func calculation(
        from journeyPage: JourneyPage,
        origin: LocationPoint,
        destination: LocationPoint,
        page: RouteSearchPage,
        stage: RouteCalculationStage = .final
    ) -> RouteCalculation? {
        var journeys = journeyPage.journeys
        if case let .earlier(boundary, limit) = page {
            journeys = journeys.filter { $0.effectiveDeparture < boundary }
            journeys = Array(journeys.suffix(limit))
        } else if case let .later(boundary, limit) = page {
            journeys = Array(journeys.filter { $0.effectiveDeparture > boundary }.prefix(limit))
        }
        let options = journeys.map { option(from: $0, origin: origin, destination: destination) }
        guard !options.isEmpty else { return nil }
        return RouteCalculation(options: options, stage: stage, selectedOptionID: options.first?.id)
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
        // MobiliteitKit preserves every GTFS mode. The app's preference remains
        // a presentation preference until the package's route-type mask has a
        // lossless representation for extended GTFS route types (e.g. 900).
        let modes: TransitModeMask = .all
        return RoutingPreferences(
            maxTransfers: 1,
            minimumTransferSeconds: filters.avoidTightTransfers ? 180 : 120,
            allowedModes: modes,
            wheelchair: filters.preferAccessible ? .required : .noPreference
        )
    }

    private nonisolated func option(
        from journey: MobiliteitKit.Journey,
        origin: LocationPoint,
        destination: LocationPoint
    ) -> RouteOption {
        let legs = journey.legs.compactMap { leg -> RoutePlan.Leg? in
            switch leg {
            case let .walk(walk):
                return RoutePlan.Leg(
                    id: "walk-\(walk.departure.timeIntervalSince1970)", mode: .walking,
                    transportKind: .walking, origin: point(walk.from), destination: point(walk.to),
                    departureTime: walk.departure, arrivalTime: walk.arrival,
                    distanceMeters: walk.distanceMeters,
                    mapCoordinates: walk.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    roadRoutingHint: walk.source == .provider ? .walking : .none
                )
            case let .transit(transit):
                let delayed = transit.effectiveDeparture > transit.scheduledDeparture || transit.effectiveArrival > transit.scheduledArrival
                return RoutePlan.Leg(
                    id: "transit-\(transit.tripID)-\(transit.board.stop.id)-\(transit.alight.stop.id)",
                    mode: mode(transit.route.type), transportKind: .transit,
                    routeName: transit.route.shortName ?? transit.route.longName,
                    headsign: transit.headsign, routeId: transit.route.id, tripId: transit.tripID,
                    originStopId: transit.board.stop.id, destinationStopId: transit.alight.stop.id,
                    stopCount: transit.intermediateStops.count + 1,
                    origin: point(transit.board.stop), destination: point(transit.alight.stop),
                    departureTime: transit.effectiveDeparture, arrivalTime: transit.effectiveArrival,
                    scheduledDepartureTime: transit.scheduledDeparture, scheduledArrivalTime: transit.scheduledArrival,
                    realtimeDepartureTime: delayed ? transit.effectiveDeparture : nil,
                    realtimeArrivalTime: delayed ? transit.effectiveArrival : nil,
                    platform: transit.board.platform,
                    delayMinutes: delayed ? Int(transit.effectiveDeparture.timeIntervalSince(transit.scheduledDeparture) / 60) : nil,
                    liveStatus: delayed ? .delayed : .scheduled
                )
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
        return RouteOption(id: journey.id.value, plan: plan, mapOverlay: overlay.segments.isEmpty ? nil : overlay)
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
    private nonisolated func mode(_ value: Int) -> TransportMode { switch value { case 0...2: .train; case 3, 700...799: .bus; case 900...999: .tram; case 7: .funicular; default: .unknown } }
}

/// Owns the expensive immutable MobiliteitKit routing snapshot. A fingerprint
/// switches the cache when the GTFS service publishes a new generation file.
actor MobiliteitRouteEngine {
    private let walkingProvider: any WalkingRoutingProvider

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

    init(walkingProvider: any WalkingRoutingProvider = MapKitWalkingProvider()) {
        self.walkingProvider = walkingProvider
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
                    try await TransitRouter(
                        databaseURL: databaseURL,
                        walkingProvider: walkingProvider
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

private extension RouteOption {
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
        var walkingDurationDelta: TimeInterval = 0
        var walkingDistanceDelta: Double = 0
        let legs = plan.legs.enumerated().map { index, leg -> RoutePlan.Leg in
            let request = WalkingGeometryRequest(origin: leg.origin, destination: leg.destination)
            guard leg.transportKind == .walking,
                  leg.roadRoutingHint == .walking,
                  let route = routesByLeg[request.key]
            else { return leg }

            let oldDuration = leg.departureTime.flatMap { departure in
                leg.arrivalTime.map { $0.timeIntervalSince(departure) }
            }
            let mapKitDuration = route.expectedTravelTime.flatMap { duration in
                duration.isFinite && duration >= 0 ? duration : nil
            }
            if let oldDuration, let mapKitDuration {
                walkingDurationDelta += mapKitDuration - oldDuration
            }
            if let oldDistance = leg.distanceMeters {
                walkingDistanceDelta += route.distanceMeters - oldDistance
            }

            var departureTime = leg.departureTime
            var arrivalTime = leg.arrivalTime
            if let mapKitDuration {
                if plan.legs.indices.contains(index + 1),
                   plan.legs[index + 1].transportKind == .transit,
                   let fixedArrival = arrivalTime {
                    departureTime = fixedArrival.addingTimeInterval(-mapKitDuration)
                } else if let fixedDeparture = departureTime {
                    arrivalTime = fixedDeparture.addingTimeInterval(mapKitDuration)
                } else if let fixedArrival = arrivalTime {
                    departureTime = fixedArrival.addingTimeInterval(-mapKitDuration)
                }
            }
            var replacement = RoutePlan.Leg(
                id: leg.id,
                mode: leg.mode,
                instruction: leg.instruction,
                transportKind: leg.transportKind,
                routeName: leg.routeName,
                headsign: leg.headsign,
                routeId: leg.routeId,
                tripId: leg.tripId,
                originStopId: leg.originStopId,
                destinationStopId: leg.destinationStopId,
                stopCount: leg.stopCount,
                origin: leg.origin,
                destination: leg.destination,
                departureTime: departureTime,
                arrivalTime: arrivalTime,
                scheduledDepartureTime: departureTime,
                scheduledArrivalTime: arrivalTime,
                realtimeDepartureTime: leg.realtimeDepartureTime,
                realtimeArrivalTime: leg.realtimeArrivalTime,
                distanceMeters: route.distanceMeters,
                mapCoordinates: route.coordinates,
                roadRoutingHint: leg.roadRoutingHint,
                platform: leg.platform,
                delayMinutes: leg.delayMinutes,
                liveStatus: leg.liveStatus,
                transferWarning: leg.transferWarning,
                bikeShareDetails: leg.bikeShareDetails
            )
            replacement.departureTimingSource = leg.departureTimingSource
            replacement.arrivalTimingSource = leg.arrivalTimingSource
            replacement.requiredTransferSeconds = leg.requiredTransferSeconds
            return replacement
        }
        return replacingLegs(
            legs,
            expectedTravelTime: plan.expectedTravelTime.map {
                max(0, $0 + walkingDurationDelta)
            },
            distanceMeters: plan.distanceMeters.map {
                max(0, $0 + walkingDistanceDelta)
            }
        )
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
        return RouteOption(id: id, plan: updatedPlan, mapOverlay: overlay.isEmpty ? nil : overlay)
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
            polyline: [request.source, request.destination]
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
