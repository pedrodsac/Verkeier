import CoreLocation
import Foundation
import MapKit

actor PublicTransportRoutingEngine {
    let gtfsService: any GTFSService
    let atpClient: any ATPClient
    let bikeShareService: any BikeShareService
    let roadRouteProvider: any RoadRouteProviding
    let now: @Sendable () -> Date
    let calendar: Calendar

    nonisolated let offlineMode: Bool
    nonisolated let accessRadiusMeters = 900.0
    nonisolated let destinationRadiusMeters = 900.0
    /// Minimum slack allowed between a transit arrival and the next boarding. Offline
    /// mode raises this to 15 min to absorb delays it can't see (no live data).
    nonisolated let transferBufferSeconds: Int
    // Connections with at most this slack are flagged "tight" for the rider,
    // even though they're still feasible (>= transferBufferSeconds).
    nonisolated let tightTransferThresholdSeconds = 2 * 60
    nonisolated let searchHorizonSeconds = 4 * 60 * 60
    nonisolated let maximumTransitLegs = 3
    nonisolated let walkingSpeedMetersPerSecond = 1.33
    /// Estimated vel’OH! speed because MapKit has no bicycle directions API.
    nonisolated let bikeSpeedMetersPerSecond = 15_000.0 / 3_600.0
    nonisolated let bikeUnlockSeconds = 120
    nonisolated let bikeAvailabilityStaleAfter: TimeInterval = 15 * 60
    nonisolated let evaluatedCandidateLimit = 10
    nonisolated let returnedOptionLimit = 5
    /// Below this, an access/egress walk is too short to be worth showing as its own leg.
    nonisolated let minimumWalkLegMeters = 25.0
    /// Penalties at or above this mark a journey as effectively infeasible (cancelled /
    /// broken connection) so arrive-by ranking sinks them below the soft no-realtime nudge.
    nonisolated let severePenaltyThreshold = 1000
    // Time-equivalent cost of one transfer when ranking journeys. 5 minutes is a
    // common transit-routing value; raise it to bias harder towards fewer transfers.
    nonisolated let transferPenaltySeconds = 300
    /// Map geometry is useful, but it must never hold route cards hostage. A
    /// provider that is slow or unavailable simply leaves GTFS geometry in place.
    nonisolated let roadGeometryBudgetSeconds: TimeInterval
    /// Departure boards are shared by several candidate journeys in one search and
    /// commonly across a quick manual recalculation. Keep the snapshot short-lived
    /// so missing realtime data degrades to a clearly labelled schedule-only leg.
    let realtimeBoardCacheLifetime: TimeInterval = 20
    /// ATP is optional enrichment. A feed that stalls is allowed only this short
    /// window before the already-computed schedule result is published.
    nonisolated let realtimeBoardBudgetSeconds: TimeInterval
    let concurrency: RouteCalculationConcurrency
    let routeSearchContextCache: RouteSearchContextCache?
    var cachedContext: CachedRouteSearchContext?
    var roadRouteCache: [RoadRouteCacheKey: RoadRoute?] = [:]
    var cachedDepartureBoards: [String: CachedDepartureBoard] = [:]

    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        bikeShareService: any BikeShareService,
        roadRouteProvider: any RoadRouteProviding,
        offlineMode: Bool,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar,
        concurrency: RouteCalculationConcurrency = .default,
        realtimeBoardBudgetSeconds: TimeInterval = 2,
        roadGeometryBudgetSeconds: TimeInterval = 1
    ) {
        self.gtfsService = gtfsService
        self.atpClient = atpClient
        self.bikeShareService = bikeShareService
        self.roadRouteProvider = roadRouteProvider
        self.offlineMode = offlineMode
        self.now = now
        self.calendar = calendar
        self.concurrency = concurrency
        self.realtimeBoardBudgetSeconds = realtimeBoardBudgetSeconds
        self.roadGeometryBudgetSeconds = roadGeometryBudgetSeconds
        self.routeSearchContextCache = (gtfsService as? LocalGTFSService)?.routeSearchContextCache
        transferBufferSeconds = offlineMode ? 15 * 60 : 120
    }

    func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime = .leaveNow,
        filters: RoutePlannerFilters = RoutePlannerFilters(),
        forceRealtimeRefresh: Bool = false,
        page: RouteSearchPage = .initial
    ) async throws -> RouteCalculation {
        try Task.checkCancellation()
        guard page.resultLimit > 0 else { throw RoutingError.noPublicTransportRoute }

        // Bike availability is optional enrichment. Refresh it independently so a
        // slow JCDecaux request cannot delay a direct bus or tram result; routing
        // uses the latest snapshot already held by the service.
        Task { @concurrent [bikeShareService] in
            await bikeShareService.refreshAvailability()
        }
        async let timetableTask = gtfsService.timetableIndex()
        try Task.checkCancellation()
        let bikeStations = await bikeShareService.bikeShareStations(
            near: from
        )
        try Task.checkCancellation()
        guard let timetable = await timetableTask, !timetable.trips.isEmpty else {
            throw RoutingError.timetableUnavailable
        }
        try Task.checkCancellation()

        // Departures search forward from their requested time. Arrive-by searches
        // backward from the deadline, so later connections remain viable labels.
        let requestNow: Date
        let arriveByLimit: Date?
        switch page {
        case .initial:
            switch time {
            case .leaveNow:
                requestNow = now()
                arriveByLimit = nil
            case let .departAt(date):
                requestNow = date
                arriveByLimit = nil
            case let .arriveBy(date):
                requestNow = date
                arriveByLimit = date
            }
        case let .earlier(boundary, _), let .later(boundary, _):
            requestNow = boundary
            arriveByLimit = nil
        }

        let staticContext = try await cachedStaticContext(for: timetable, now: requestNow)
        let baseContext = RouteSearchContext(staticContext: staticContext, now: requestNow)
        guard !baseContext.activeTrips.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        // Keep the first result schedule-only. A force refresh resolves exact
        // endpoint walks before searching so live catchability can be revalidated.
        let context = if forceRealtimeRefresh {
            await contextWithWalkingDistances(
                from: from,
                to: to,
                context: baseContext,
                bikeStations: bikeStations
            )
        } else {
            baseContext
        }

        let kernel = RouteSearchKernel(engine: self)
        let arriveBy = arriveByLimit != nil

        // The timetable graph search and direct bike search are independent. Both
        // are immutable operations over the same snapshot and can run concurrently;
        // serial mode deliberately executes them one after the other for repeatable
        // test and benchmark baselines.
        var transitBaseCandidates: [ScheduledJourney]
        let directBikeCandidates: [ScheduledJourney]
        if concurrency.cpuWorkerLimit == 1 {
            transitBaseCandidates = try await routeCalculationConcurrent {
                try Task.checkCancellation()
                return kernel.transitJourneys(
                    from: from,
                    to: to,
                    context: context,
                    arriveBy: arriveBy,
                    filters: filters,
                    includeLiveReserves: forceRealtimeRefresh,
                    page: page
                )
            }
            directBikeCandidates = try await routeCalculationConcurrent { () -> [ScheduledJourney] in
                try Task.checkCancellation()
                guard case .initial = page else { return [] }
                return kernel.directBikeJourneys(
                    from: from,
                    to: to,
                    stations: bikeStations,
                    context: context,
                    arriveByDeadlineSeconds: arriveByLimit == nil
                        ? nil
                        : context.currentSeconds
                )
            }
        } else {
            async let transitTask = routeCalculationConcurrent {
                try Task.checkCancellation()
                return kernel.transitJourneys(
                    from: from,
                    to: to,
                    context: context,
                    arriveBy: arriveBy,
                    filters: filters,
                    includeLiveReserves: forceRealtimeRefresh,
                    page: page
                )
            }
            async let directBikeTask: [ScheduledJourney] = routeCalculationConcurrent {
                try Task.checkCancellation()
                guard case .initial = page else { return [] }
                return kernel.directBikeJourneys(
                    from: from,
                    to: to,
                    stations: bikeStations,
                    context: context,
                    arriveByDeadlineSeconds: arriveByLimit == nil
                        ? nil
                        : context.currentSeconds
                )
            }
            transitBaseCandidates = try await transitTask
            directBikeCandidates = try await directBikeTask
        }
        if transitBaseCandidates.isEmpty, filters != RoutePlannerFilters() {
            transitBaseCandidates = try await routeCalculationConcurrent {
                try Task.checkCancellation()
                return kernel.transitJourneys(
                    from: from,
                    to: to,
                    context: context,
                    arriveBy: arriveBy,
                    filters: RoutePlannerFilters(),
                    includeLiveReserves: forceRealtimeRefresh,
                    page: page
                )
            }
        }
        let resolvedTransitCandidates = transitBaseCandidates
        let mixedBikeCandidates: [ScheduledJourney] = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            guard case .initial = page else { return [] }
            return kernel.mixedBikeJourneys(
                from: resolvedTransitCandidates,
                stations: bikeStations,
                context: context
            )
        }
        let scheduledCandidates = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            return kernel.combinedScheduledCandidates(
                transit: resolvedTransitCandidates,
                mixedBike: mixedBikeCandidates,
                directBike: directBikeCandidates,
                filters: filters
            )
        }

        guard !scheduledCandidates.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        try Task.checkCancellation()

        // Arrive-by wants the latest journey you can still board in time; leave-now
        // and depart-at use the rider-selected sort order (Fastest = earliest arrival).
        let preferLatestDeparture: Bool = switch page {
        case .earlier:
            true
        case .initial, .later:
            arriveByLimit != nil
        }

        // Keep low-transfer journeys alive through truncation: drop only journeys that
        // are strictly worse on every axis, then rank by the same rider-selected
        // objective the planner screen uses.
        let selectedScheduled = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            return kernel.selectScheduledCandidates(
                scheduledCandidates,
                arriveBy: preferLatestDeparture,
                filters: filters
            )
        }

        // Live departure boards are intentionally fetched before final ranking so a
        // delayed incoming ride can be repaired into a different, still-catchable
        // suffix (for example: bus 223 → the next T1), rather than merely being
        // labelled as a broken version of its scheduled itinerary.
        let scheduledForLiveSearch = Array(selectedScheduled)
        let enrichment = try await enrich(
            scheduledForLiveSearch,
            context: context,
            forceRealtimeRefresh: forceRealtimeRefresh
        )
        let enrichedCandidates = enrichment.candidates
        let invalidatedOptionIDs: Set<String> = Set(enrichedCandidates.compactMap { candidate in
            guard candidate.penalty >= severePenaltyThreshold else { return nil }
            return optionID(for: candidate.legs, origin: from, destination: to)
        })
        let repairs = try await repairedCandidates(
            from: enrichedCandidates,
            origin: from,
            destination: to,
            context: context,
            filters: filters,
            boardsByStopId: enrichment.boardsByStopId
        )
        let repairedOriginalSignatures = Set(repairs.map(\.originalSignature))
        let candidatesAfterRepair = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            return enrichedCandidates.filter {
                !repairedOriginalSignatures.contains($0.signature)
            } + repairs.map(\.candidate)
        }
        let geometryCandidates = if forceRealtimeRefresh {
            try await self.roadRoutedCandidates(candidatesAfterRepair)
        } else {
            candidatesAfterRepair
        }
        let sortedCandidates = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            return kernel.selectEnrichedCandidates(
                geometryCandidates,
                arriveBy: preferLatestDeparture,
                deadline: arriveByLimit,
                limit: page.resultLimit,
                filters: filters
            )
        }
        let options = try await routeOptions(
            from: sortedCandidates,
            origin: from,
            destination: to,
            context: context
        )

        guard !options.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        let primaryOptions = Array(options.filter { !$0.usesBikeShare }.prefix(page.resultLimit))
        let supplementalOptions = Array(options.filter(\.usesBikeShare).prefix(1))
        let selectedOptionID = primaryOptions.first?.id ?? supplementalOptions.first?.id
        return RouteCalculation(
            options: primaryOptions,
            supplementalOptions: supplementalOptions,
            invalidatedOptionIDs: invalidatedOptionIDs,
            selectedOptionID: selectedOptionID
        )
    }

    func cachedStaticContext(
        for timetable: GTFSTimetableIndexPayload,
        now: Date
    ) async throws -> CachedRouteSearchContext {
        let key = RouteSearchCacheKey(timetable: timetable, calendar: calendar, now: now)
        let calendar = calendar
        let build: @Sendable () async throws -> CachedRouteSearchContext = {
            try await routeCalculationConcurrent {
                try Task.checkCancellation()
                return CachedRouteSearchContext(
                    key: key,
                    timetable: timetable,
                    calendar: calendar,
                    now: now
                )
            }
        }
        let context: CachedRouteSearchContext
        if let routeSearchContextCache {
            context = try await routeSearchContextCache.context(for: key, build: build)
        } else if let cachedContext, cachedContext.key == key {
            context = cachedContext
        } else {
            context = try await build()
        }
        cachedContext = context
        return context
    }
}
