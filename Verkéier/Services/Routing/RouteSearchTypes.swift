import CoreLocation
import Foundation

/// Bounds the concurrent work performed by one route calculation.
///
/// The limits are deliberately small because realtime boards and MapKit route
/// requests are shared system/network resources, while the CPU limit keeps a
/// large GTFS search from competing with the rest of the app.
nonisolated struct RouteCalculationConcurrency: Hashable, Sendable {
    let cpuWorkerLimit: Int
    let realtimeBoardLimit: Int
    let roadRouteLimit: Int

    init(
        cpuWorkerLimit: Int = 4,
        realtimeBoardLimit: Int = 4,
        roadRouteLimit: Int = 4
    ) {
        self.cpuWorkerLimit = max(1, cpuWorkerLimit)
        self.realtimeBoardLimit = max(1, realtimeBoardLimit)
        self.roadRouteLimit = max(1, roadRouteLimit)
    }

    static let `default` = RouteCalculationConcurrency()
    static let serial = RouteCalculationConcurrency(
        cpuWorkerLimit: 1,
        realtimeBoardLimit: 1,
        roadRouteLimit: 1
    )
}

/// The explicit boundary between the actor-owned routing coordinator and the
/// immutable route-search work that may run on a concurrent executor.
///
/// The underlying engine contains only nonisolated pure methods for the work
/// exposed here. Keeping this small wrapper avoids sharing the engine's mutable
/// departure and road caches with worker tasks.
nonisolated struct RouteSearchKernel: Sendable {
    private let engine: PublicTransportRoutingEngine

    init(engine: PublicTransportRoutingEngine) {
        self.engine = engine
    }

    func transitJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        arriveBy: Bool,
        filters: RoutePlannerFilters,
        includeLiveReserves: Bool,
        page: RouteSearchPage
    ) -> [ScheduledJourney] {
        engine.profileScheduledJourneys(
            from: origin,
            to: destination,
            context: context,
            arriveBy: arriveBy,
            filters: filters,
            includeLiveReserves: includeLiveReserves,
            page: page
        )
    }

    func directBikeJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        stations: [BikeShareStation],
        context: RouteSearchContext,
        arriveByDeadlineSeconds: Int?
    ) -> [ScheduledJourney] {
        engine.bikeJourneys(
            from: origin,
            to: destination,
            stations: stations,
            context: context,
            arriveByDeadlineSeconds: arriveByDeadlineSeconds
        )
    }

    func mixedBikeJourneys(
        from candidates: [ScheduledJourney],
        stations: [BikeShareStation],
        context: RouteSearchContext
    ) -> [ScheduledJourney] {
        engine.mixedBikeJourneys(from: candidates, stations: stations, context: context)
    }

    func combinedScheduledCandidates(
        transit: [ScheduledJourney],
        mixedBike: [ScheduledJourney],
        directBike: [ScheduledJourney],
        filters _: RoutePlannerFilters
    ) -> [ScheduledJourney] {
        var candidates = transit
        candidates.append(contentsOf: mixedBike)
        candidates.append(contentsOf: directBike)
        candidates = engine.deduplicatedJourneys(candidates.map {
            ScheduledJourney(legs: engine.retimedWalkingLegs($0.legs))
        })

        return candidates
    }

    func selectScheduledCandidates(
        _ candidates: [ScheduledJourney],
        arriveBy: Bool,
        filters: RoutePlannerFilters
    ) -> [ScheduledJourney] {
        guard !candidates.isEmpty else { return [] }

        let transit = candidates.filter { !engine.isBikeShareJourney($0) }
        let bikeShare = candidates
            .filter(engine.isBikeShareJourney)
            .sorted { engine.scheduledRanksBefore($0, $1, filters: filters) }
        let orderedTransit = transit.sorted {
            if $0.departureTime != $1.departureTime {
                return arriveBy
                    ? $0.departureTime > $1.departureTime
                    : $0.departureTime < $1.departureTime
            }
            return engine.scheduledRanksBefore($0, $1, filters: filters)
        }
        return Array(orderedTransit.prefix(engine.evaluatedCandidateLimit))
            + Array(bikeShare.prefix(1))
    }

    func selectEnrichedCandidates(
        _ candidates: [RouteCandidate],
        arriveBy: Bool,
        deadline: Date?,
        limit: Int,
        filters: RoutePlannerFilters
    ) -> [RouteCandidate] {
        let transit = candidates.filter {
            !$0.legs.contains { $0.transportKind == .bikeShare }
        }
        let primary = engine.enrichedDepartureProfile(
            transit,
            arriveBy: arriveBy,
            deadline: deadline,
            limit: limit
        )
        let bikeShare = candidates.filter {
            $0.legs.contains { $0.transportKind == .bikeShare }
        }.sorted { engine.candidateRanksBefore($0, $1, filters: filters) }.first
        var result = primary
        if let bikeShare {
            result.append(bikeShare)
        }
        return result
    }

    func retimed(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        engine.retimedWalkingLegs(legs)
    }

    func deduplicated(_ candidates: [ScheduledJourney]) -> [ScheduledJourney] {
        engine.deduplicatedJourneys(candidates)
    }

    func enrichedCandidates(
        _ candidates: [ScheduledJourney],
        boardsByStopId: [String: [Departure]]
    ) -> [RouteCandidate] {
        engine.enrichedCandidates(candidates, boardsByStopId: boardsByStopId)
    }

    func realtimeStopIDs(for candidates: [ScheduledJourney]) -> Set<String> {
        Set(candidates.flatMap { journey in
            journey.legs.compactMap { leg in
                leg.transportKind == .transit ? leg.originStopId : nil
            }
        })
    }

    func firstUnusableTransitIndex(in legs: [RoutePlan.Leg]) -> Int? {
        engine.firstUnusableTransitIndex(in: legs)
    }

    func repairStart(
        for candidate: RouteCandidate,
        brokenTransitIndex: Int,
        origin: LocationPoint,
        context: RouteSearchContext
    ) -> (
        origin: LocationPoint,
        context: RouteSearchContext,
        prefix: [RoutePlan.Leg],
        prefixTransitLegCount: Int
    )? {
        engine.repairStart(
            for: candidate,
            brokenTransitIndex: brokenTransitIndex,
            origin: origin,
            context: context
        )
    }

    func matchesModePreference(
        _ candidate: RouteCandidate,
        filters: RoutePlannerFilters
    ) -> Bool {
        engine.matchesModePreference(candidate, filters: filters)
    }

    func repairJobs(
        from candidates: [RouteCandidate],
        origin: LocationPoint,
        destination: LocationPoint,
        context: RouteSearchContext
    ) throws -> [RealtimeRepairJob] {
        var jobs: [RealtimeRepairJob] = []
        for candidate in candidates {
            try Task.checkCancellation()
            guard let brokenTransitIndex = engine.firstUnusableTransitIndex(in: candidate.legs),
                  let repairStart = engine.repairStart(
                      for: candidate,
                      brokenTransitIndex: brokenTransitIndex,
                      origin: origin,
                      context: context
                  ) else {
                continue
            }

            let suffixes = engine.profileScheduledJourneys(
                from: repairStart.origin,
                to: destination,
                context: repairStart.context,
                arriveBy: false,
                filters: RoutePlannerFilters(),
                includeLiveReserves: false,
                candidateLimit: 6
            )
            for suffix in suffixes.prefix(6) {
                try Task.checkCancellation()
                guard repairStart.prefixTransitLegCount + suffix.transitLegCount
                    <= engine.maximumTransitLegs else {
                    continue
                }

                jobs.append(RealtimeRepairJob(
                    originalSignature: candidate.signature,
                    journey: ScheduledJourney(
                        legs: engine.normalizedWalkingLegs(repairStart.prefix + suffix.legs)
                    )
                ))
            }
        }
        return jobs
    }
}

/// Runs synchronous, immutable routing work away from the caller's executor.
/// Cancellation is wired explicitly because this is the one place where a
/// concurrent task is intentionally created to use the global executor.
nonisolated func routeCalculationConcurrent<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
) async throws -> T {
    let task = Task { @concurrent in
        try operation()
    }
    return try await withTaskCancellationHandler(
        operation: { try await task.value },
        onCancel: { task.cancel() }
    )
}

nonisolated struct RouteSearchContext: Sendable {
    private let staticContext: CachedRouteSearchContext
    private let walkingDistances: [RoadRouteCacheKey: Double]
    private let effectiveTrips: [GTFSTimetableTripEntry]?
    private let effectiveIndex: TransitSearchIndex?
    let coverage: RouteSearchCoverage?

    var scheduledTrips: [GTFSTimetableTripEntry] { staticContext.activeTrips }
    var allStops: [GTFSTimetableStopEntry] { staticContext.stops }
    var transferRules: [GTFSTimetableTransferEntry] { staticContext.transferRules }
    let now: Date
    let currentSeconds: Int

    var serviceStart: Date {
        staticContext.serviceStart
    }

    var stopsById: [String: GTFSTimetableStopEntry] {
        staticContext.stopsById
    }

    var routesById: [String: GTFSTimetableRouteEntry] {
        staticContext.routesById
    }

    var shapesById: [String: GTFSTimetableShapeEntry] {
        staticContext.shapesById
    }

    var activeTrips: [GTFSTimetableTripEntry] {
        effectiveTrips ?? staticContext.activeTrips
    }

    var transfersByFromStopId: [String: [GTFSTimetableTransferEntry]] {
        staticContext.transfersByFromStopId
    }

    var sameStopMinimumTransferSecondsByStopId: [String: Int] {
        staticContext.sameStopMinimumTransferSecondsByStopId
    }

    var transitIndex: TransitSearchIndex {
        effectiveIndex ?? staticContext.transitIndex
    }

    func nearbyStops(to point: LocationPoint, radiusMeters: Double) -> [GTFSTimetableStopEntry] {
        staticContext.nearbyStops(to: point, radiusMeters: radiusMeters)
    }

    init(
        staticContext: CachedRouteSearchContext,
        now: Date,
        walkingDistances: [RoadRouteCacheKey: Double] = [:],
        effectiveTrips: [GTFSTimetableTripEntry]? = nil,
        effectiveIndex: TransitSearchIndex? = nil,
        coverage: RouteSearchCoverage? = nil
    ) {
        self.staticContext = staticContext
        self.walkingDistances = walkingDistances
        self.effectiveTrips = effectiveTrips
        self.effectiveIndex = effectiveIndex
        self.coverage = coverage
        self.now = now
        currentSeconds = max(0, Int(now.timeIntervalSince(staticContext.serviceStart)))
    }

    /// Returns a road distance when it has been resolved for this calculation,
    /// otherwise the straight-line distance used as a safe search fallback.
    func walkingDistanceMeters(from origin: LocationPoint, to destination: LocationPoint) -> Double {
        let key = RoadRouteCacheKey(
            origin: RouteMapCoordinate(origin),
            destination: RouteMapCoordinate(destination),
            transport: .walking
        )
        return walkingDistances[key]
            ?? routeSearchDistanceMeters(from: origin, to: destination)
    }

    func withWalkingDistances(_ walkingDistances: [RoadRouteCacheKey: Double]) -> RouteSearchContext {
        RouteSearchContext(
            staticContext: staticContext,
            now: now,
            walkingDistances: self.walkingDistances.merging(walkingDistances) { _, new in new },
            effectiveTrips: effectiveTrips, effectiveIndex: effectiveIndex, coverage: coverage
        )
    }

    /// Returns a search context anchored at an effective (potentially live-retimed)
    /// instant while preserving the same immutable timetable indexes.
    func rebased(at seconds: Int) -> RouteSearchContext {
        RouteSearchContext(
            staticContext: staticContext,
            now: serviceStart.addingTimeInterval(TimeInterval(seconds)),
            walkingDistances: walkingDistances,
            effectiveTrips: effectiveTrips, effectiveIndex: effectiveIndex, coverage: coverage
        )
    }
}

nonisolated struct CachedRouteSearchContext: Sendable {
    let key: RouteSearchCacheKey
    let stops: [GTFSTimetableStopEntry]
    let transferRules: [GTFSTimetableTransferEntry]
    let serviceStart: Date
    let stopsById: [String: GTFSTimetableStopEntry]
    let spatialCellDegrees: Double
    let stopsBySpatialCell: [GridCell: [GTFSTimetableStopEntry]]
    let routesById: [String: GTFSTimetableRouteEntry]
    let shapesById: [String: GTFSTimetableShapeEntry]
    let activeTrips: [GTFSTimetableTripEntry]
    let transfersByFromStopId: [String: [GTFSTimetableTransferEntry]]
    let sameStopMinimumTransferSecondsByStopId: [String: Int]
    let transitIndex: TransitSearchIndex

    init(
        key: RouteSearchCacheKey,
        timetable: GTFSTimetableIndexPayload,
        calendar: Calendar,
        now: Date
    ) {
        self.key = key
        stops = timetable.stops
        transferRules = Self.expandedTransferRules(timetable.transfers, stops: timetable.stops)
        serviceStart = Self.serviceStart(on: now, calendar: calendar)
        stopsById = Dictionary(uniqueKeysWithValues: timetable.stops.map { ($0.id, $0) })
        spatialCellDegrees = 0.0025
        stopsBySpatialCell = Dictionary(grouping: timetable.stops) {
            GridCell(stop: $0, cellDegrees: 0.0025)
        }
        routesById = Dictionary(uniqueKeysWithValues: timetable.routes.map { ($0.id, $0) })
        shapesById = Dictionary(uniqueKeysWithValues: timetable.shapes.map { ($0.id, $0) })

        // Cache a whole service date, not the adjacent-day slice of its first query.
        // GTFS times are elapsed seconds from local noon minus twelve hours.
        let longestTripSeconds = timetable.trips.compactMap { $0.stopTimes.last?.arrivalSeconds }.max() ?? 86400
        let precedingDays = max(1, longestTripSeconds / 86400 + 1)
        var combinedTrips: [GTFSTimetableTripEntry] = []
        for dayOffset in (-precedingDays)...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let services = Self.activeServiceIds(in: timetable.services, on: day, calendar: calendar)
            let offset = Int(Self.serviceStart(on: day, calendar: calendar).timeIntervalSince(serviceStart))
            let serviceDate = RouteSearchCacheKey.gtfsDateString(from: day, calendar: calendar)
            for trip in timetable.trips where services.contains(trip.serviceId) {
                let shiftedTrip = Self.shifted(trip, by: offset, serviceDate: serviceDate)
                guard (shiftedTrip.stopTimes.last?.arrivalSeconds ?? .min) >= -6 * 3600,
                      (shiftedTrip.stopTimes.first?.departureSeconds ?? .max) <= 35 * 3600 else { continue }
                combinedTrips.append(shiftedTrip)
            }
        }

        activeTrips = combinedTrips
        let transfers = Self.transfers(
            stops: timetable.stops,
            declaredTransfers: transferRules
        )
        transfersByFromStopId = transfers
        sameStopMinimumTransferSecondsByStopId = timetable.transfers.reduce(into: [:]) { result, transfer in
            guard transfer.fromStopId == transfer.toStopId,
                  let minimum = transfer.minimumTransferSeconds else { return }
            result[transfer.fromStopId] = max(result[transfer.fromStopId, default: 0], minimum)
        }
        transitIndex = TransitSearchIndex(
            stops: timetable.stops,
            trips: combinedTrips,
            transfersByFromStopId: transfers
        )
    }

    func nearbyStops(to point: LocationPoint, radiusMeters: Double) -> [GTFSTimetableStopEntry] {
        let base = GridCell(point: point, cellDegrees: spatialCellDegrees)
        // A cell is roughly 250 m north/south. Use the same conservative range for
        // longitude, which remains safely inclusive at Luxembourg's latitude.
        let cellRadius = max(1, Int((radiusMeters / 200).rounded(.up)))
        var result: [GTFSTimetableStopEntry] = []
        result.reserveCapacity(32)
        for deltaLatitude in -cellRadius ... cellRadius {
            for deltaLongitude in -cellRadius ... cellRadius {
                result.append(contentsOf: stopsBySpatialCell[
                    GridCell(
                        latitude: base.latitude + deltaLatitude,
                        longitude: base.longitude + deltaLongitude
                    ),
                    default: []
                ])
            }
        }
        return result
    }

    static func serviceStart(on date: Date, calendar: Calendar) -> Date {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        return noon.addingTimeInterval(-12 * 3600)
    }

    private static func shifted(
        _ trip: GTFSTimetableTripEntry, by seconds: Int, serviceDate: String
    ) -> GTFSTimetableTripEntry {
        GTFSTimetableTripEntry(
            id: "\(trip.id)#\(serviceDate)", routeId: trip.routeId, serviceId: trip.serviceId,
            headsign: trip.headsign, directionId: trip.directionId, shapeId: trip.shapeId,
            originalTripID: trip.id, serviceDate: serviceDate,
            stopTimes: trip.stopTimes.map { time in
                GTFSTimetableStopTimeEntry(
                    stopId: time.stopId, arrivalSeconds: time.arrivalSeconds + seconds,
                    departureSeconds: time.departureSeconds + seconds, sequence: time.sequence,
                    headsign: time.headsign, pickupType: time.pickupType, dropOffType: time.dropOffType,
                    shapeDistanceTraveled: time.shapeDistanceTraveled
                )
            }
        )
    }

    private static func expandedTransferRules(
        _ rules: [GTFSTimetableTransferEntry], stops: [GTFSTimetableStopEntry]
    ) -> [GTFSTimetableTransferEntry] {
        let children = Dictionary(grouping: stops.filter { $0.parentStation != nil }, by: { $0.parentStation! })
        return rules.flatMap { rule in
            let origins = children[rule.fromStopId]?.map(\.id) ?? [rule.fromStopId]
            let destinations = children[rule.toStopId]?.map(\.id) ?? [rule.toStopId]
            return origins.flatMap { from in destinations.map { to in
                GTFSTimetableTransferEntry(
                    fromStopId: from, toStopId: to, minimumTransferSeconds: rule.minimumTransferSeconds,
                    transferType: rule.transferType, fromRouteID: rule.fromRouteID, toRouteID: rule.toRouteID,
                    fromTripID: rule.fromTripID, toTripID: rule.toTripID
                )
            } }
        }
    }

    /// Declared `transfers.txt` edges augmented with synthesised foot-transfers between
    /// stops within walking range — so riders can change lines at stations split across
    /// platform stop IDs (or between adjacent stops) even when the feed omits them.
    private static func transfers(
        stops: [GTFSTimetableStopEntry],
        declaredTransfers: [GTFSTimetableTransferEntry]
    ) -> [String: [GTFSTimetableTransferEntry]] {
        var grouped = Dictionary(grouping: declaredTransfers, by: \.fromStopId)
        var seenPairs = Set(declaredTransfers.map { "\($0.fromStopId)|\($0.toStopId)" })

        // ponytail: grid bucketing keeps this near-linear; swap for a KD-tree only if the
        // full feed makes context rebuilds slow.
        let radiusMeters = 200.0
        let cellDegrees = 0.0025 // ~250 m, a touch wider than the radius
        var grid: [GridCell: [GTFSTimetableStopEntry]] = [:]
        for stop in stops {
            grid[GridCell(stop: stop, cellDegrees: cellDegrees), default: []].append(stop)
        }

        for stop in stops {
            let base = GridCell(stop: stop, cellDegrees: cellDegrees)
            for deltaLatitude in -1 ... 1 {
                for deltaLongitude in -1 ... 1 {
                    let neighbours = grid[
                        GridCell(
                            latitude: base.latitude + deltaLatitude,
                            longitude: base.longitude + deltaLongitude
                        ),
                        default: []
                    ]
                    for other in neighbours where other.id != stop.id {
                        let pair = "\(stop.id)|\(other.id)"
                        guard !seenPairs.contains(pair),
                              routeSearchDistanceMeters(from: stop.location, to: other.location) <= radiusMeters else {
                            continue
                        }
                        seenPairs.insert(pair)
                        grouped[stop.id, default: []].append(
                            GTFSTimetableTransferEntry(
                                fromStopId: stop.id,
                                toStopId: other.id,
                                minimumTransferSeconds: nil
                            )
                        )
                    }
                }
            }
        }
        return grouped
    }

    private static func activeServiceIds(
        in services: [GTFSTimetableServiceEntry],
        on date: Date,
        calendar: Calendar
    ) -> Set<String> {
        let dateString = RouteSearchCacheKey.gtfsDateString(from: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: date)

        return Set(services.compactMap { service in
            if service.removedDates.contains(dateString) {
                return nil
            }
            if service.addedDates.contains(dateString) {
                return service.id
            }
            guard service.weekdays.contains(weekday) else {
                return nil
            }
            if let startDate = service.startDate, startDate > dateString {
                return nil
            }
            if let endDate = service.endDate, endDate < dateString {
                return nil
            }
            return service.id
        })
    }
}

/// Retains the expensive, immutable timetable indexes independently of a route
/// service instance. SwiftUI may recreate the service value while redrawing the
/// planner, but the loaded timetable and its derived indexes should remain hot.
actor RouteSearchContextCache {
    private var cachedContext: CachedRouteSearchContext?

    func context(
        for key: RouteSearchCacheKey,
        build: @Sendable () async throws -> CachedRouteSearchContext
    ) async throws -> CachedRouteSearchContext {
        if let cachedContext, cachedContext.key == key {
            return cachedContext
        }

        let context = try await build()
        cachedContext = context
        return context
    }

    func removeAll() {
        cachedContext = nil
    }
}

nonisolated struct RouteSearchCacheKey: Equatable, Sendable {
    let source: String
    let revision: String
    let timeZoneID: String
    let date: String
    let stopCount: Int
    let routeCount: Int
    let serviceCount: Int
    let tripCount: Int
    let transferCount: Int
    let shapeCount: Int

    init(timetable: GTFSTimetableIndexPayload, calendar: Calendar, now: Date) {
        source = timetable.source
        revision = timetable.revision ?? String(timetable.hashValue)
        timeZoneID = calendar.timeZone.identifier
        date = Self.gtfsDateString(from: now, calendar: calendar)
        stopCount = timetable.stops.count
        routeCount = timetable.routes.count
        serviceCount = timetable.services.count
        tripCount = timetable.trips.count
        transferCount = timetable.transfers.count
        shapeCount = timetable.shapes.count
    }

    static func gtfsDateString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// A fixed-size lat/lon bucket used to find nearby stops without an O(n²) scan.
nonisolated struct GridCell: Hashable, Sendable {
    let latitude: Int
    let longitude: Int

    init(latitude: Int, longitude: Int) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(stop: GTFSTimetableStopEntry, cellDegrees: Double) {
        latitude = Int((stop.latitude / cellDegrees).rounded(.down))
        longitude = Int((stop.longitude / cellDegrees).rounded(.down))
    }

    init(point: LocationPoint, cellDegrees: Double) {
        latitude = Int((point.latitude / cellDegrees).rounded(.down))
        longitude = Int((point.longitude / cellDegrees).rounded(.down))
    }
}

nonisolated struct StopCandidate: Sendable {
    let stop: GTFSTimetableStopEntry
    let distanceMeters: Double
}

nonisolated struct ScheduledJourney: Sendable {
    let legs: [RoutePlan.Leg]

    var arrivalTime: Date {
        legs.compactMap(\.arrivalTime).last ?? .distantFuture
    }

    var departureTime: Date {
        legs.compactMap(\.departureTime).first ?? .distantPast
    }

    var firstTransitDeparture: Date {
        legs.first { $0.transportKind == .transit }
            .flatMap { $0.scheduledDepartureTime ?? $0.departureTime }
            ?? legs.first.flatMap { $0.scheduledDepartureTime ?? $0.departureTime }
            ?? .distantPast
    }

    /// Scheduled arrival of the first transit leg — later means the rider stays aboard
    /// the first vehicle longer before changing.
    var firstTransitAlightTime: Date {
        legs.first { $0.transportKind == .transit }
            .flatMap { $0.scheduledArrivalTime ?? $0.arrivalTime } ?? .distantPast
    }

    var totalWalkingMeters: Double {
        legs.lazy
            .filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    var transitLegCount: Int {
        legs.reduce(0) { $0 + ($1.transportKind == .transit ? 1 : 0) }
    }

    /// Identity for "the same journey": the ordered vehicle trips ridden. Itineraries
    /// differing only in where they board/change between the same trips share this.
    var tripSignature: String {
        let trips = legs.compactMap { leg -> String? in
            guard leg.transportKind == .transit else { return nil }
            return leg.tripId ?? leg.routeId ?? leg.id
        }
        return trips.isEmpty ? signature : trips.joined(separator: ">")
    }

    var signature: String {
        legs.map { leg in
            [
                leg.transportKind.rawValue,
                leg.routeId ?? leg.routeName ?? leg.id,
                leg.originStopId ?? leg.origin.id,
                leg.destinationStopId ?? leg.destination.id,
                String(Int((leg.scheduledDepartureTime ?? leg.departureTime)?.timeIntervalSince1970 ?? 0)),
                String(Int((leg.scheduledArrivalTime ?? leg.arrivalTime)?.timeIntervalSince1970 ?? 0))
            ].joined(separator: "|")
        }.joined(separator: "->")
    }
}

nonisolated struct RouteCandidate: Sendable {
    let legs: [RoutePlan.Leg]
    let penalty: Int

    var arrivalTime: Date {
        legs.compactMap(\.arrivalTime).last ?? .distantFuture
    }

    var firstTransitDeparture: Date {
        legs.first { $0.transportKind == .transit }
            .flatMap { $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime }
            ?? legs.first.flatMap { $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime }
            ?? .distantPast
    }

    var departureTime: Date {
        legs.first.flatMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        } ?? .distantPast
    }

    var totalWalkingMeters: Double {
        legs.lazy
            .filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    var transitLegCount: Int {
        legs.reduce(0) { $0 + ($1.transportKind == .transit ? 1 : 0) }
    }

    var signature: String {
        legs.map { leg in
            [
                leg.transportKind.rawValue,
                leg.routeId ?? leg.routeName ?? leg.id,
                leg.originStopId ?? leg.origin.id,
                leg.destinationStopId ?? leg.destination.id,
                String(Int((leg.scheduledDepartureTime ?? leg.departureTime)?.timeIntervalSince1970 ?? 0)),
                String(Int((leg.scheduledArrivalTime ?? leg.arrivalTime)?.timeIntervalSince1970 ?? 0))
            ].joined(separator: "|")
        }.joined(separator: "->")
    }
}

/// A live-data repair replaces the broken suffix of a scheduled candidate. Keeping
/// the original signature lets the caller suppress only that now-obsolete version,
/// while unrelated broken fallbacks remain visible when no repair is available.
nonisolated struct RealtimeRouteRepair: Sendable {
    let originalSignature: String
    let candidate: RouteCandidate
}

nonisolated struct RealtimeRepairJob: Sendable {
    let originalSignature: String
    let journey: ScheduledJourney
}

nonisolated struct CachedDepartureBoard: Sendable {
    let departures: [Departure]
    let fetchedAt: Date
}

nonisolated struct RoadRouteCacheKey: Hashable, Sendable {
    let transport: RoadRouteTransport
    let originLatitude: Double
    let originLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double

    init(
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) {
        self.transport = transport
        originLatitude = origin.latitude
        originLongitude = origin.longitude
        destinationLatitude = destination.latitude
        destinationLongitude = destination.longitude
    }
}

nonisolated func routeSearchDistanceMeters(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
    let earthRadius = 6_371_000.0
    let lat1 = lhs.latitude * .pi / 180
    let lat2 = rhs.latitude * .pi / 180
    let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
    let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180

    let a = sin(deltaLat / 2) * sin(deltaLat / 2)
        + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
}
