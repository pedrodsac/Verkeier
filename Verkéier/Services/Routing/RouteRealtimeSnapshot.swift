import Foundation

nonisolated struct RouteTripInstanceID: Hashable, Sendable {
    let tripID: String
    let serviceDate: String
}

nonisolated struct RouteBoardRequest: Hashable, Sendable {
    let stopID: String
    let windowStart: Date
    var durationMinutes = 30

    var options: ATPDepartureBoardOptions {
        ATPDepartureBoardOptions(date: windowStart, durationMinutes: durationMinutes,
                                 maximumJourneys: 100, includePasslist: true)
    }
}

/// A write-only search trace. Snapshot times themselves never change during a scan.
nonisolated final class RouteSearchCoverage: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: Set<RouteBoardRequest> = []
    private var walks: Set<RoadRouteCacheKey> = []

    func record(stopID: String, from seconds: Int, through end: Int, serviceStart: Date) {
        let start = serviceStart.addingTimeInterval(TimeInterval(seconds))
        let finish = serviceStart.addingTimeInterval(TimeInterval(end))
        let firstSlot = Int(floor(start.timeIntervalSince1970 / 1800))
        let lastSlot = Int(floor(finish.timeIntervalSince1970 / 1800))
        guard firstSlot <= lastSlot else { return }
        lock.withLock {
            for slot in firstSlot...lastSlot {
                requests.insert(RouteBoardRequest(stopID: stopID, windowStart: Date(timeIntervalSince1970: Double(slot * 1800))))
            }
        }
    }

    func recordWalk(from: LocationPoint, to: LocationPoint) {
        _ = lock.withLock { walks.insert(RoadRouteCacheKey(origin: RouteMapCoordinate(from), destination: RouteMapCoordinate(to), transport: .walking)) }
    }

    func snapshot() -> (boards: Set<RouteBoardRequest>, walks: Set<RoadRouteCacheKey>) {
        lock.withLock { (requests, walks) }
    }
}

/// Numeric ATP extIds and zero-padded GTFS platform IDs identify the same stop.
nonisolated func routingStopID(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.allSatisfy(\.isNumber) else { return value }
    let trimmed = value.drop(while: { $0 == "0" })
    return trimmed.isEmpty ? "0" : String(trimmed)
}

nonisolated struct RouteRealtimeSnapshot: Sendable {
    let trips: [GTFSTimetableTripEntry]
    let matchedReferences: [String: String]

    init(context: RouteSearchContext, boards: [ATPRoutingBoard], references: [String: String] = [:]) {
        let scheduled = context.scheduledTrips
        var positionsByStop: [String: [(Int, Int)]] = [:]
        for (tripIndex, trip) in scheduled.enumerated() {
            for (position, time) in trip.stopTimes.enumerated() {
                positionsByStop[routingStopID(time.stopId), default: []].append((tripIndex, position))
            }
        }
        var matches: [Int: [(ATPRoutingJourney, Int)]] = [:]
        var confirmed = references
        for journey in boards.flatMap(\.journeys).sorted(by: {
            ($0.departure.lastUpdated ?? .distantPast) < ($1.departure.lastUpdated ?? .distantPast)
        }) {
            let departure = journey.departure
            guard let planned = departure.scheduledDeparture else { continue }
            let expectedSeconds = Int(planned.timeIntervalSince(context.serviceStart).rounded())
            let referenceKey = departure.journeyReference.map { "\($0)|\(Int(planned.timeIntervalSince1970 / 86400))" }
            let candidates = positionsByStop[routingStopID(departure.stopId), default: []].filter { tripIndex, position in
                let trip = scheduled[tripIndex]
                guard let route = context.routesById[trip.routeId],
                      abs(trip.stopTimes[position].departureSeconds - expectedSeconds) <= 60,
                      departure.routeId == route.id || departure.lineName.caseInsensitiveCompare(route.shortName) == .orderedSame else { return false }
                if let key = referenceKey, let known = confirmed[key], known != trip.id { return false }
                let direction = departure.destination.normalizedForSearch
                if !direction.isEmpty {
                    let names = [trip.headsign, trip.stopTimes[position].headsign]
                        + trip.stopTimes.dropFirst(position + 1).map { context.stopsById[$0.stopId]?.name }
                    guard names.compactMap({ $0?.normalizedForSearch }).contains(direction) else { return false }
                }
                // Check every known passlist occurrence against this trip, in order.
                var lastPosition = -1
                for stop in journey.stops {
                    let occurrences = trip.stopTimes.indices.filter { index in
                        guard index > lastPosition,
                              routingStopID(trip.stopTimes[index].stopId) == routingStopID(stop.stopID) else { return false }
                        if let time = stop.scheduledDeparture ?? stop.scheduledArrival {
                            let actual = stop.scheduledDeparture == nil ? trip.stopTimes[index].arrivalSeconds : trip.stopTimes[index].departureSeconds
                            return abs(Double(actual) - time.timeIntervalSince(context.serviceStart)) <= 60
                        }
                        return true
                    }
                    guard occurrences.count == 1, let occurrence = occurrences.first else { return false }
                    lastPosition = occurrence
                }
                return true
            }
            // Never choose the closest of multiple plausible vehicles.
            guard candidates.count == 1, let (tripIndex, position) = candidates.first else { continue }
            matches[tripIndex, default: []].append((journey, position))
            if let key = referenceKey { confirmed[key] = scheduled[tripIndex].id }
        }
        matchedReferences = confirmed
        trips = scheduled.enumerated().map { tripIndex, trip in
            guard let observations = matches[tripIndex] else { return trip }
            var updates: [Int: ATPRoutingStopPrediction] = [:]
            var cancelled = false
            for (journey, anchor) in observations {
                cancelled = journey.departure.isCancelled
                var anchorUpdate = updates[anchor] ?? ATPRoutingStopPrediction(stopID: journey.departure.stopId)
                if let predicted = journey.departure.realtimeDeparture {
                    anchorUpdate.predictedDeparture = predicted
                } else if let delay = journey.departure.delayMinutes, let planned = journey.departure.scheduledDeparture {
                    anchorUpdate.predictedDeparture = planned.addingTimeInterval(Double(delay * 60))
                }
                anchorUpdate.platform = journey.departure.platform ?? anchorUpdate.platform
                updates[anchor] = anchorUpdate
                var cursor = -1
                for stop in journey.stops {
                    guard let position = trip.stopTimes.indices.first(where: { index in
                        guard index > cursor, routingStopID(trip.stopTimes[index].stopId) == routingStopID(stop.stopID) else { return false }
                        guard let date = stop.scheduledDeparture ?? stop.scheduledArrival else { return true }
                        let seconds = stop.scheduledDeparture == nil ? trip.stopTimes[index].arrivalSeconds : trip.stopTimes[index].departureSeconds
                        return abs(Double(seconds) - date.timeIntervalSince(context.serviceStart)) <= 60
                    }) else { continue }
                    cursor = position
                    let old = updates[position]
                    var merged = stop
                    merged.predictedArrival = stop.predictedArrival ?? old?.predictedArrival
                    merged.predictedDeparture = stop.predictedDeparture ?? old?.predictedDeparture
                    merged.platform = stop.platform ?? old?.platform
                    updates[position] = merged
                }
            }
            var carriedDelay: Int?
            var previousDeparture = Int.min
            let times = trip.stopTimes.enumerated().map { position, time in
                let update = updates[position]
                let observedArrival = update?.predictedArrival.map { Int($0.timeIntervalSince(context.serviceStart).rounded()) }
                let observedDeparture = update?.predictedDeparture.map { Int($0.timeIntervalSince(context.serviceStart).rounded()) }
                if let observedArrival { carriedDelay = observedArrival - time.arrivalSeconds }
                // A boarding prediction can estimate this stop's arrival when no arrival is published.
                let arrivalDelay = carriedDelay ?? observedDeparture.map { $0 - time.departureSeconds }
                let arrival = max(previousDeparture, observedArrival ?? (time.arrivalSeconds + (arrivalDelay ?? 0)))
                if let observedDeparture { carriedDelay = observedDeparture - time.departureSeconds }
                let departure = max(arrival, observedDeparture ?? (time.departureSeconds + (carriedDelay ?? 0)))
                let arrivalSource: RouteTimingSource = observedArrival != nil ? .observed : (arrivalDelay != nil ? .estimated : .scheduled)
                let departureSource: RouteTimingSource = observedDeparture != nil ? .observed : (carriedDelay != nil ? .estimated : .scheduled)
                previousDeparture = departure
                return GTFSTimetableStopTimeEntry(
                    stopId: time.stopId, arrivalSeconds: arrival, departureSeconds: departure,
                    sequence: time.sequence, headsign: time.headsign,
                    pickupType: cancelled || update?.boardingCancelled == true ? "1" : time.pickupType,
                    dropOffType: cancelled || update?.alightingCancelled == true ? "1" : time.dropOffType,
                    shapeDistanceTraveled: time.shapeDistanceTraveled,
                    scheduledArrivalSeconds: time.arrivalSeconds, scheduledDepartureSeconds: time.departureSeconds,
                    arrivalSource: arrivalSource, departureSource: departureSource, livePlatform: update?.platform
                )
            }
            return GTFSTimetableTripEntry(
                id: trip.id, routeId: trip.routeId, serviceId: trip.serviceId, headsign: trip.headsign,
                directionId: trip.directionId, shapeId: trip.shapeId,
                originalTripID: trip.originalTripID, serviceDate: trip.serviceDate, stopTimes: times
            )
        }
    }
}
