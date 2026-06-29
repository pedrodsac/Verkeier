import CoreLocation
import Foundation
import HeapModule

nonisolated struct RouteSearchContext {
    private let staticContext: CachedRouteSearchContext
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
        staticContext.activeTrips
    }

    var tripReferencesByStopId: [String: [TripStopReference]] {
        staticContext.tripReferencesByStopId
    }

    var transfersByFromStopId: [String: [GTFSTimetableTransferEntry]] {
        staticContext.transfersByFromStopId
    }

    init(staticContext: CachedRouteSearchContext, now: Date) {
        self.staticContext = staticContext
        self.now = now
        currentSeconds = max(0, Int(now.timeIntervalSince(staticContext.serviceStart)))
    }
}

nonisolated struct CachedRouteSearchContext {
    let key: RouteSearchCacheKey
    let serviceStart: Date
    let stopsById: [String: GTFSTimetableStopEntry]
    let routesById: [String: GTFSTimetableRouteEntry]
    let shapesById: [String: GTFSTimetableShapeEntry]
    let activeTrips: [GTFSTimetableTripEntry]
    let tripReferencesByStopId: [String: [TripStopReference]]
    let transfersByFromStopId: [String: [GTFSTimetableTransferEntry]]

    init(
        key: RouteSearchCacheKey,
        timetable: GTFSTimetableIndexPayload,
        calendar: Calendar,
        now: Date
    ) {
        self.key = key
        serviceStart = calendar.startOfDay(for: now)
        stopsById = Dictionary(uniqueKeysWithValues: timetable.stops.map { ($0.id, $0) })
        routesById = Dictionary(uniqueKeysWithValues: timetable.routes.map { ($0.id, $0) })
        shapesById = Dictionary(uniqueKeysWithValues: timetable.shapes.map { ($0.id, $0) })

        let activeServiceIds = Self.activeServiceIds(
            in: timetable.services,
            on: now,
            calendar: calendar
        )
        var combinedTrips = timetable.trips.filter { activeServiceIds.contains($0.serviceId) }

        // GTFS service days run past 24:00, so a just-after-midnight search must also see
        // yesterday's late trips. Pull the previous day's services and shift their
        // midnight-crossing trips back a day onto today's clock.
        let previousDay = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let previousServiceIds = Self.activeServiceIds(
            in: timetable.services,
            on: previousDay,
            calendar: calendar
        )
        let yesterdayLateTrips = timetable.trips
            .filter { previousServiceIds.contains($0.serviceId) }
            .filter { ($0.stopTimes.map(\.departureSeconds).max() ?? 0) >= Self.secondsPerDay }
            .map { Self.shiftedBackADay($0) }
        combinedTrips.append(contentsOf: yesterdayLateTrips)

        var references: [String: [TripStopReference]] = [:]
        for tripIndex in combinedTrips.indices {
            let trip = combinedTrips[tripIndex]
            for stopTimeIndex in trip.stopTimes.indices.dropLast() {
                let stopTime = trip.stopTimes[stopTimeIndex]
                references[stopTime.stopId, default: []].append(
                    TripStopReference(tripIndex: tripIndex, stopTimeIndex: stopTimeIndex)
                )
            }
        }
        let sortedReferences = references.mapValues {
            $0.sorted {
                combinedTrips[$0.tripIndex].stopTimes[$0.stopTimeIndex].departureSeconds
                    < combinedTrips[$1.tripIndex].stopTimes[$1.stopTimeIndex].departureSeconds
            }
        }

        activeTrips = combinedTrips
        tripReferencesByStopId = sortedReferences
        transfersByFromStopId = Self.transfers(
            stops: timetable.stops,
            declaredTransfers: timetable.transfers
        )
    }

    private static let secondsPerDay = 86400

    /// Re-stamps a trip's stop times a day earlier so a previous-service-day trip that
    /// crosses midnight (e.g. `24:30`) lines up with today's `serviceStart` clock.
    private static func shiftedBackADay(_ trip: GTFSTimetableTripEntry) -> GTFSTimetableTripEntry {
        GTFSTimetableTripEntry(
            id: "\(trip.id)#prev",
            routeId: trip.routeId,
            serviceId: trip.serviceId,
            headsign: trip.headsign,
            directionId: trip.directionId,
            shapeId: trip.shapeId,
            stopTimes: trip.stopTimes.map { stopTime in
                GTFSTimetableStopTimeEntry(
                    stopId: stopTime.stopId,
                    arrivalSeconds: stopTime.arrivalSeconds - secondsPerDay,
                    departureSeconds: stopTime.departureSeconds - secondsPerDay,
                    sequence: stopTime.sequence,
                    headsign: stopTime.headsign,
                    pickupType: stopTime.pickupType,
                    dropOffType: stopTime.dropOffType,
                    shapeDistanceTraveled: stopTime.shapeDistanceTraveled
                )
            }
        )
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

nonisolated struct RouteSearchCacheKey: Equatable {
    let source: String
    let date: String
    let stopCount: Int
    let routeCount: Int
    let serviceCount: Int
    let tripCount: Int
    let transferCount: Int
    let shapeCount: Int

    init(timetable: GTFSTimetableIndexPayload, calendar: Calendar, now: Date) {
        source = timetable.source
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

nonisolated struct TripStopReference {
    let tripIndex: Int
    let stopTimeIndex: Int
}

/// A fixed-size lat/lon bucket used to find nearby stops without an O(n²) scan.
nonisolated struct GridCell: Hashable {
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
}

nonisolated struct StopCandidate {
    let stop: GTFSTimetableStopEntry
    let distanceMeters: Double
}

nonisolated struct JourneyState: Comparable {
    let stopId: String
    let readySeconds: Int
    let legs: [RoutePlan.Leg]
    let transitLegCount: Int
    let visitedStopIds: Set<String>

    static func < (lhs: JourneyState, rhs: JourneyState) -> Bool {
        lhs.readySeconds < rhs.readySeconds
    }
}

nonisolated struct ScheduledJourney {
    let legs: [RoutePlan.Leg]

    var arrivalTime: Date {
        legs.compactMap(\.arrivalTime).last ?? .distantFuture
    }

    var departureTime: Date {
        legs.compactMap(\.departureTime).first ?? .distantPast
    }

    var firstTransitDeparture: Date {
        legs.first { $0.transportKind == .transit }
            .flatMap { $0.scheduledDepartureTime ?? $0.departureTime } ?? .distantPast
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

nonisolated struct RouteCandidate {
    let legs: [RoutePlan.Leg]
    let penalty: Int

    var arrivalTime: Date {
        legs.compactMap(\.arrivalTime).last ?? .distantFuture
    }

    var firstTransitDeparture: Date {
        legs.first { $0.transportKind == .transit }
            .flatMap { $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime } ?? .distantPast
    }

    var transitLegCount: Int {
        legs.reduce(0) { $0 + ($1.transportKind == .transit ? 1 : 0) }
    }
}

nonisolated struct RoadRouteCacheKey: Hashable {
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

nonisolated struct JourneyPriorityQueue {
    private var storage = Heap<QueuedJourneyState>()
    private var nextSequence = 0

    var isEmpty: Bool {
        storage.isEmpty
    }

    mutating func push(_ element: JourneyState) {
        storage.insert(QueuedJourneyState(state: element, sequence: nextSequence))
        nextSequence += 1
    }

    mutating func popMin() -> JourneyState? {
        storage.popMin()?.state
    }
}

nonisolated struct QueuedJourneyState: Comparable {
    let state: JourneyState
    let sequence: Int

    static func < (lhs: QueuedJourneyState, rhs: QueuedJourneyState) -> Bool {
        if lhs.state.readySeconds != rhs.state.readySeconds {
            return lhs.state.readySeconds < rhs.state.readySeconds
        }
        return lhs.sequence < rhs.sequence
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
