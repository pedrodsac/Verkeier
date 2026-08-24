import CoreLocation
import Foundation
import HeapModule
import MapKit

actor PublicTransportRoutingEngine {
    let gtfsService: any GTFSService
    let atpClient: any ATPClient
    let bikeShareService: any BikeShareService
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
    let maximumTransitLegs = 3
    let walkingSpeedMetersPerSecond = 1.33
    /// Estimated vel’OH! speed because MapKit has no bicycle directions API.
    let bikeSpeedMetersPerSecond = 15_000.0 / 3_600.0
    let bikeUnlockSeconds = 120
    let bikeAvailabilityStaleAfter: TimeInterval = 15 * 60
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
        bikeShareService: any BikeShareService,
        roadRouteProvider: any RoadRouteProviding,
        offlineMode: Bool,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.gtfsService = gtfsService
        self.atpClient = atpClient
        self.bikeShareService = bikeShareService
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
        await bikeShareService.refreshAvailability()
        let bikeStations = await bikeShareService.bikeShareStations(
            near: from
        )
        guard let timetable = await gtfsService.timetableIndex(), !timetable.trips.isEmpty else {
            throw RoutingError.timetableUnavailable
        }

        // Departures search forward from their requested time. Arrive-by searches
        // backward from the deadline, so later connections remain viable labels.
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
            requestNow = date
            arriveByLimit = date
        }

        let staticContext = cachedStaticContext(for: timetable, now: requestNow)
        let context = RouteSearchContext(staticContext: staticContext, now: requestNow)
        guard !context.activeTrips.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        var scheduledCandidates = if arriveByLimit != nil {
            arriveByJourneys(from: from, to: to, context: context)
        } else {
            scheduledJourneys(from: from, to: to, context: context)
        }
        let transitBaseCandidates = scheduledCandidates
        scheduledCandidates.append(contentsOf: mixedBikeJourneys(
            from: transitBaseCandidates,
            stations: bikeStations,
            context: context
        ))
        scheduledCandidates.append(contentsOf: bikeJourneys(
            from: from,
            to: to,
            stations: bikeStations,
            context: context,
            arriveByDeadlineSeconds: arriveByLimit == nil ? nil : context.currentSeconds
        ))
        scheduledCandidates = deduplicatedJourneys(scheduledCandidates.map {
            ScheduledJourney(legs: retimedWalkingLegs($0.legs))
        })

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
        let scheduledPool = if arriveByLimit != nil {
            // A scheduled-dominated journey may become the best fallback once a later
            // departure is cancelled or predicted late. Keep those alternatives until
            // realtime has established the actual arrive-by frontier.
            scheduledCandidates
        } else {
            paretoFiltered(
                scheduledCandidates,
                departure: \.departureTime,
                arrival: \.arrivalTime,
                transfers: \.transitLegCount
            )
        }
        let selectedScheduled = scheduledPool
        .sorted { lhs, rhs in
            if preferLatestDeparture {
                arriveByRanksBefore(lhs, rhs, filters: filters)
            } else {
                scheduledComfortCostSeconds(lhs) < scheduledComfortCostSeconds(rhs)
            }
        }
        .prefix(evaluatedCandidateLimit)

        let enrichedCandidates = await enrich(Array(selectedScheduled), context: context)
        let enrichedPool = if arriveByLimit != nil {
            // Penalty/deadline class is part of arrive-by dominance. The generic
            // scheduled frontier does not know about either and could otherwise drop
            // the only connected, on-time alternative before final ranking.
            enrichedCandidates
        } else {
            paretoFiltered(
                enrichedCandidates,
                departure: \.departureTime,
                arrival: \.arrivalTime,
                transfers: \.transitLegCount
            )
        }
        let sortedCandidates = enrichedPool
        .sorted { lhs, rhs in
            if let arriveByLimit {
                arriveByRanksBefore(lhs, rhs, deadline: arriveByLimit, filters: filters)
            } else {
                comfortCostSeconds(lhs) < comfortCostSeconds(rhs)
            }
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
