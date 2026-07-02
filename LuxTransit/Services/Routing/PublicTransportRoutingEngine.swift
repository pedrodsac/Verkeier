import CoreLocation
import Foundation
import HeapModule
import MapKit

actor PublicTransportRoutingEngine {
    let gtfsService: any GTFSService
    let atpClient: any ATPClient
    let roadRouteProvider: any RoadRouteProviding
    let now: @Sendable () -> Date
    let calendar: Calendar

    let offlineMode: Bool
    let accessRadiusMeters = 900.0
    let destinationRadiusMeters = 900.0
    /// Minimum slack allowed between a transit arrival and the next boarding. Offline
    /// mode raises this to 15 min to absorb delays it can't see (no live data).
    let transferBufferSeconds: Int
    // Connections with less than this slack are flagged "tight" for the rider,
    // even though they're still feasible (>= transferBufferSeconds).
    let tightTransferThresholdSeconds = 300
    let searchHorizonSeconds = 4 * 60 * 60
    // ponytail: arrive-by reuses the forward search from this far before the target
    // and filters to journeys arriving in time; widen if long journeys get dropped.
    let arriveByLookbackSeconds: TimeInterval = 3 * 60 * 60
    let maximumTransitLegs = 3
    let walkingSpeedMetersPerSecond = 1.33
    let evaluatedCandidateLimit = 18
    let returnedOptionLimit = 18
    /// Below this, an access/egress walk is too short to be worth showing as its own leg.
    let minimumWalkLegMeters = 25.0
    /// Penalties at or above this mark a journey as effectively infeasible (cancelled /
    /// broken connection) so arrive-by ranking sinks them below the soft no-realtime nudge.
    let severePenaltyThreshold = 1000
    // Time-equivalent cost of one transfer when ranking journeys. 5 minutes is a
    // common transit-routing value; raise it to bias harder towards fewer transfers.
    let transferPenaltySeconds = 300
    var cachedContext: CachedRouteSearchContext?
    var roadRouteCoordinateCache: [RoadRouteCacheKey: [RouteMapCoordinate]?] = [:]

    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        roadRouteProvider: any RoadRouteProviding,
        offlineMode: Bool,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.gtfsService = gtfsService
        self.atpClient = atpClient
        self.roadRouteProvider = roadRouteProvider
        self.offlineMode = offlineMode
        self.now = now
        self.calendar = calendar
        transferBufferSeconds = offlineMode ? 15 * 60 : 120
    }

    func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime = .leaveNow,
        filters: RoutePlannerFilters = RoutePlannerFilters()
    ) async throws -> RouteCalculation {
        guard let timetable = await gtfsService.timetableIndex(), !timetable.trips.isEmpty else {
            throw RoutingError.timetableUnavailable
        }

        // The forward search is anchored at `requestNow`. "Leave at" anchors there
        // directly; "arrive by" anchors a few hours earlier and filters results to
        // those reaching the destination in time.
        let requestNow: Date
        let arriveByLimit: Date?
        switch time {
        case .leaveNow:
            requestNow = now()
            arriveByLimit = nil
        case let .departAt(date):
            requestNow = date
            arriveByLimit = nil
        case let .arriveBy(date):
            requestNow = date.addingTimeInterval(-arriveByLookbackSeconds)
            arriveByLimit = date
        }

        let staticContext = cachedStaticContext(for: timetable, now: requestNow)
        let context = RouteSearchContext(staticContext: staticContext, now: requestNow)
        guard !context.activeTrips.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        var scheduledCandidates = scheduledJourneys(from: from, to: to, context: context)
        if let arriveByLimit {
            scheduledCandidates = scheduledCandidates.filter { $0.arrivalTime <= arriveByLimit }
        }

        // Honour a mode preference before truncation, so a valid (e.g.) tram itinerary
        // can't be discarded by cheaper buses. Relax if nothing matches rather than
        // returning no route — the view model surfaces the "closest alternatives" note.
        if let preferredMode = filters.modePreference.transportMode {
            let preferred = scheduledCandidates.filter { journey in
                journey.legs.contains { $0.transportKind == .transit && $0.mode == preferredMode }
            }
            if !preferred.isEmpty {
                scheduledCandidates = preferred
            }
        }

        guard !scheduledCandidates.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        try Task.checkCancellation()

        // Arrive-by wants the latest journey you can still board in time; everything
        // else wants the lowest comfort cost (earliest arrival + transfer penalty).
        let preferLatestDeparture = arriveByLimit != nil

        // Keep low-transfer journeys alive through truncation: drop only journeys that
        // are strictly worse on every axis, then rank by the active objective rather
        // than the earliest-arriving alone.
        let selectedScheduled = paretoFiltered(
            scheduledCandidates,
            departure: \.firstTransitDeparture,
            arrival: \.arrivalTime,
            transfers: \.transitLegCount
        )
        .sorted { lhs, rhs in
            preferLatestDeparture
                ? departsLater(lhs, rhs)
                : scheduledComfortCostSeconds(lhs) < scheduledComfortCostSeconds(rhs)
        }
        .prefix(evaluatedCandidateLimit)

        let enrichedCandidates = await enrich(Array(selectedScheduled), context: context)
        let sortedCandidates = paretoFiltered(
            enrichedCandidates,
            departure: \.firstTransitDeparture,
            arrival: \.arrivalTime,
            transfers: \.transitLegCount
        )
        .sorted { lhs, rhs in
            preferLatestDeparture
                ? departsLater(lhs, rhs)
                : comfortCostSeconds(lhs) < comfortCostSeconds(rhs)
        }
        .prefix(returnedOptionLimit)
        var options: [RouteOption] = []
        options.reserveCapacity(sortedCandidates.count)
        for candidate in sortedCandidates {
            if let option = await routeOption(
                from: candidate,
                origin: from,
                destination: to,
                context: context
            ) {
                options.append(option)
            }
        }

        guard !options.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        let selectedOptionID = options.first?.id
        return RouteCalculation(options: options, selectedOptionID: selectedOptionID)
    }

    func cachedStaticContext(
        for timetable: GTFSTimetableIndexPayload,
        now: Date
    ) -> CachedRouteSearchContext {
        let key = RouteSearchCacheKey(timetable: timetable, calendar: calendar, now: now)
        if let cachedContext, cachedContext.key == key {
            return cachedContext
        }

        let context = CachedRouteSearchContext(
            key: key,
            timetable: timetable,
            calendar: calendar,
            now: now
        )
        cachedContext = context
        return context
    }
}
