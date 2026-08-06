import CoreLocation
import Foundation
import HeapModule
import MapKit

extension PublicTransportRoutingEngine {
    /// Builds direct vel’OH! alternatives. Bike stations are represented as
    /// ordinary journey nodes so the result can be combined with transit
    /// candidates by the same enrichment and presentation pipeline.
    func bikeJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        stations: [BikeShareStation],
        context: RouteSearchContext
    ) -> [ScheduledJourney] {
        let usable = stations.filter { $0.isOpen != false }
        guard usable.count >= 2 else { return [] }

        let candidates = usable.flatMap { pickup in
            usable.compactMap { dropoff -> ScheduledJourney? in
                guard pickup.id != dropoff.id else { return nil }

                let accessDistance = routeSearchDistanceMeters(from: origin, to: pickup.location)
                let bikeDistance = routeSearchDistanceMeters(from: pickup.location, to: dropoff.location)
                let egressDistance = routeSearchDistanceMeters(from: dropoff.location, to: destination)
                guard bikeDistance >= 100 else { return nil }

                let accessSeconds = walkingSeconds(for: accessDistance)
                let bikeSeconds = max(60, Int((bikeDistance / bikeSpeedMetersPerSecond).rounded(.up)))
                    + bikeUnlockSeconds
                let egressSeconds = walkingSeconds(for: egressDistance)
                let accessStart = context.currentSeconds
                let pickupTime = accessStart + accessSeconds
                let dropoffTime = pickupTime + bikeSeconds
                let arrivalTime = dropoffTime + egressSeconds
                let warning = bikeAvailabilityWarning(
                    pickup: pickup,
                    dropoff: dropoff
                )

                var legs: [RoutePlan.Leg] = []
                if accessDistance > minimumWalkLegMeters {
                    legs.append(walkingLeg(
                        id: "bike-access-\(pickup.id)",
                        from: origin,
                        to: pickup.location,
                        departureSeconds: accessStart,
                        arrivalSeconds: pickupTime,
                        serviceStart: context.serviceStart,
                        distanceMeters: accessDistance,
                        instruction: "Walk to vel’OH! station \(pickup.displayName)"
                    ))
                }

                let bikeDetails = BikeShareLegDetails(
                    pickupStation: pickup,
                    returnStation: dropoff,
                    isAvailabilityWarning: warning
                )
                legs.append(RoutePlan.Leg(
                    id: "bike-\(pickup.id)-\(dropoff.id)",
                    mode: .bicycle,
                        instruction: "Take a vel’OH! bike to \(dropoff.displayName)",
                    transportKind: .bikeShare,
                    routeName: "vel’OH!",
                    origin: pickup.location,
                    destination: dropoff.location,
                    departureTime: date(seconds: pickupTime, from: context.serviceStart),
                    arrivalTime: date(seconds: dropoffTime, from: context.serviceStart),
                    distanceMeters: bikeDistance,
                    mapCoordinates: [RouteMapCoordinate(pickup.location), RouteMapCoordinate(dropoff.location)],
                    roadRoutingHint: .bicycle,
                    bikeShareDetails: bikeDetails
                ))

                if egressDistance > minimumWalkLegMeters {
                    legs.append(walkingLeg(
                        id: "bike-egress-\(dropoff.id)",
                        from: dropoff.location,
                        to: destination,
                        departureSeconds: dropoffTime,
                        arrivalSeconds: arrivalTime,
                        serviceStart: context.serviceStart,
                        distanceMeters: egressDistance,
                        instruction: "Walk to \(destination.name ?? "your destination")"
                    ))
                }
                return ScheduledJourney(legs: legs)
            }
        }

        return candidates
            .sorted { $0.arrivalTime < $1.arrivalTime }
            .prefix(evaluatedCandidateLimit)
            .map { $0 }
    }

    /// Adds bike legs to the walking gaps already present in transit journeys.
    /// Each gap can independently become a rental, so a journey may contain
    /// multiple rentals without introducing a separate transit search engine.
    func mixedBikeJourneys(
        from baseJourneys: [ScheduledJourney],
        stations: [BikeShareStation],
        context: RouteSearchContext
    ) -> [ScheduledJourney] {
        let walkIndicesByJourney = baseJourneys.map { journey in
            journey.legs.indices.filter { journey.legs[$0].transportKind == .walking }
        }
        var results: [ScheduledJourney] = []

        for (journeyIndex, journey) in baseJourneys.enumerated() {
            let walkIndices = walkIndicesByJourney[journeyIndex]
            guard !walkIndices.isEmpty else { continue }

            var replacements: [Int: [RoutePlan.Leg]] = [:]
            for index in walkIndices {
                let walk = journey.legs[index]
                guard let departure = walk.departureTime,
                      let arrival = walk.arrivalTime else { continue }
                let departureSeconds = max(
                    context.currentSeconds,
                    Int(departure.timeIntervalSince(context.serviceStart).rounded())
                )
                let deadline = Int(arrival.timeIntervalSince(context.serviceStart).rounded())
                if let connection = bestBikeConnection(
                    from: walk.origin,
                    to: walk.destination,
                    departureSeconds: departureSeconds,
                    deadlineSeconds: deadline,
                    stations: stations,
                    context: context
                ) {
                    replacements[index] = connection
                }
            }

            guard !replacements.isEmpty else { continue }
            let indices = Array(replacements.keys).sorted()
            let subsetCount = 1 << indices.count
            for mask in 1 ..< subsetCount {
                var legs: [RoutePlan.Leg] = []
                for index in journey.legs.indices {
                    guard let subsetIndex = indices.firstIndex(of: index),
                          mask & (1 << subsetIndex) != 0,
                          let replacement = replacements[index] else {
                        legs.append(journey.legs[index])
                        continue
                    }
                    legs.append(contentsOf: replacement)
                }
                results.append(ScheduledJourney(legs: legs))
            }
        }

        return results
            .filter { $0.legs.contains { $0.transportKind == .bikeShare } }
            .sorted { $0.arrivalTime < $1.arrivalTime }
            .prefix(evaluatedCandidateLimit)
            .map { $0 }
    }

    private func bestBikeConnection(
        from origin: LocationPoint,
        to destination: LocationPoint,
        departureSeconds: Int,
        deadlineSeconds: Int?,
        stations: [BikeShareStation],
        context: RouteSearchContext
    ) -> [RoutePlan.Leg]? {
        let usable = stations.filter { $0.isOpen != false }
        var best: ([RoutePlan.Leg], Int)?
        for pickup in usable {
            for dropoff in usable where pickup.id != dropoff.id {
                let accessDistance = routeSearchDistanceMeters(from: origin, to: pickup.location)
                let bikeDistance = routeSearchDistanceMeters(from: pickup.location, to: dropoff.location)
                let egressDistance = routeSearchDistanceMeters(from: dropoff.location, to: destination)
                guard bikeDistance >= 100 else { continue }
                let accessSeconds = walkingSeconds(for: accessDistance)
                let bikeSeconds = max(60, Int((bikeDistance / bikeSpeedMetersPerSecond).rounded(.up)))
                    + bikeUnlockSeconds
                let egressSeconds = walkingSeconds(for: egressDistance)
                let pickupTime = departureSeconds + accessSeconds
                let dropoffTime = pickupTime + bikeSeconds
                let arrivalSeconds = dropoffTime + egressSeconds
                if let deadlineSeconds, arrivalSeconds > deadlineSeconds { continue }
                let score = arrivalSeconds
                guard best == nil || score < best!.1 else { continue }

                let warning = bikeAvailabilityWarning(
                    pickup: pickup,
                    dropoff: dropoff
                )
                var legs: [RoutePlan.Leg] = []
                if accessDistance > minimumWalkLegMeters {
                    legs.append(walkingLeg(
                        id: "bike-access-\(pickup.id)-\(departureSeconds)",
                        from: origin,
                        to: pickup.location,
                        departureSeconds: departureSeconds,
                        arrivalSeconds: pickupTime,
                        serviceStart: context.serviceStart,
                        distanceMeters: accessDistance,
                        instruction: "Walk to vel’OH! station \(pickup.displayName)"
                    ))
                }
                legs.append(RoutePlan.Leg(
                    id: "bike-\(pickup.id)-\(dropoff.id)-\(departureSeconds)",
                    mode: .bicycle,
                        instruction: "Take a vel’OH! bike to \(dropoff.displayName)",
                    transportKind: .bikeShare,
                    routeName: "vel’OH!",
                    origin: pickup.location,
                    destination: dropoff.location,
                    departureTime: date(seconds: pickupTime, from: context.serviceStart),
                    arrivalTime: date(seconds: dropoffTime, from: context.serviceStart),
                    distanceMeters: bikeDistance,
                    mapCoordinates: [RouteMapCoordinate(pickup.location), RouteMapCoordinate(dropoff.location)],
                    roadRoutingHint: .bicycle,
                    bikeShareDetails: BikeShareLegDetails(
                        pickupStation: pickup,
                        returnStation: dropoff,
                        isAvailabilityWarning: warning
                    )
                ))
                if egressDistance > minimumWalkLegMeters {
                    legs.append(walkingLeg(
                        id: "bike-egress-\(dropoff.id)-\(departureSeconds)",
                        from: dropoff.location,
                        to: destination,
                        departureSeconds: dropoffTime,
                        arrivalSeconds: arrivalSeconds,
                        serviceStart: context.serviceStart,
                        distanceMeters: egressDistance,
                        instruction: "Walk to \(destination.name ?? "your destination")"
                    ))
                }
                best = (legs, score)
            }
        }
        return best?.0
    }

    private func bikeAvailabilityWarning(
        pickup: BikeShareStation,
        dropoff: BikeShareStation
    ) -> Bool {
        func isStale(_ station: BikeShareStation) -> Bool {
            guard let lastUpdated = station.lastUpdated else { return true }
            return Date.now.timeIntervalSince(lastUpdated) > bikeAvailabilityStaleAfter
        }

        return pickup.bikesAvailable == nil
            || dropoff.docksAvailable == nil
            || pickup.bikesAvailable == 0
            || dropoff.docksAvailable == 0
            || isStale(pickup)
            || isStale(dropoff)
    }

    func scheduledJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext
    ) -> [ScheduledJourney] {
        let originStops = nearestStops(
            to: origin,
            in: context,
            radiusMeters: accessRadiusMeters,
            limit: 8
        )
        let destinationStops = destinationStopMatches(
            for: destination,
            in: context,
            radiusMeters: destinationRadiusMeters
        )
        guard !originStops.isEmpty, !destinationStops.isEmpty else { return [] }

        let destinationStopsById = Dictionary(uniqueKeysWithValues: destinationStops.map { ($0.stop.id, $0) })
        var queue = JourneyPriorityQueue()
        for originCandidate in originStops {
            let walkSeconds = walkingSeconds(for: originCandidate.distanceMeters)
            let accessLeg = walkingLeg(
                id: "access-\(originCandidate.stop.id)",
                from: origin,
                to: originCandidate.stop.location,
                departureSeconds: context.currentSeconds,
                arrivalSeconds: context.currentSeconds + walkSeconds,
                serviceStart: context.serviceStart,
                distanceMeters: originCandidate.distanceMeters,
                instruction: "Walk to \(originCandidate.stop.name)"
            )

            queue.push(JourneyState(
                stopId: originCandidate.stop.id,
                readySeconds: context.currentSeconds + walkSeconds,
                legs: originCandidate.distanceMeters > minimumWalkLegMeters ? [accessLeg] : [],
                transitLegCount: 0,
                visitedStopIds: [originCandidate.stop.id]
            ))
        }

        var candidates: [ScheduledJourney] = []
        var bestArrivalByStopAndLegCount: [String: Int] = [:]
        var expansionCount = 0

        while let state = queue.popMin(), expansionCount < 5000 {
            if Task.isCancelled { return [] }
            expansionCount += 1

            if let destinationCandidate = destinationStopsById[state.stopId],
               state.transitLegCount > 0 {
                let egressSeconds = walkingSeconds(for: destinationCandidate.distanceMeters)
                let egressLeg = walkingLeg(
                    id: "egress-\(state.stopId)",
                    from: context.stopsById[state.stopId]?.location ?? destinationCandidate.stop.location,
                    to: destination,
                    departureSeconds: state.readySeconds,
                    arrivalSeconds: state.readySeconds + egressSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: destinationCandidate.distanceMeters,
                    instruction: "Walk to \(destination.name ?? destinationCandidate.stop.name)"
                )
                let completeLegs = destinationCandidate.distanceMeters > minimumWalkLegMeters
                    ? state.legs + [egressLeg]
                    : state.legs
                candidates.append(ScheduledJourney(legs: completeLegs))

                if candidates.count >= evaluatedCandidateLimit {
                    continue
                }
            }

            guard state.transitLegCount < maximumTransitLegs else { continue }

            let boardingReadySeconds = state.readySeconds
                + (state.transitLegCount > 0 ? transferBufferSeconds : 0)
            guard boardingReadySeconds <= context.currentSeconds + searchHorizonSeconds else {
                continue
            }

            let references = context.tripReferencesByStopId[state.stopId, default: []]
            for reference in references {
                let trip = context.activeTrips[reference.tripIndex]
                let boardTime = trip.stopTimes[reference.stopTimeIndex]
                guard boardTime.departureSeconds >= boardingReadySeconds else {
                    continue
                }
                // References are sorted by departure time, so the horizon check is
                // monotonic (break). No-pickup is per-trip, so it must skip this trip
                // only (continue) — breaking here would drop every later departure.
                guard boardTime.departureSeconds <= context.currentSeconds + searchHorizonSeconds else {
                    break
                }
                guard boardTime.pickupType != "1" else {
                    continue
                }

                for downstreamIndex in trip.stopTimes.indices.dropFirst(reference.stopTimeIndex + 1) {
                    let alightTime = trip.stopTimes[downstreamIndex]
                    guard alightTime.dropOffType != "1",
                          alightTime.arrivalSeconds > boardTime.departureSeconds,
                          !state.visitedStopIds.contains(alightTime.stopId),
                          let boardStop = context.stopsById[boardTime.stopId],
                          let alightStop = context.stopsById[alightTime.stopId],
                          let route = context.routesById[trip.routeId] else {
                        continue
                    }

                    let isDestinationStop = destinationStopsById[alightTime.stopId] != nil
                    if !isDestinationStop {
                        // ponytail: time-only label pruning at (stop, legCount). Can drop a
                        // slightly-later arrival that would enable a strictly better
                        // continuation; add a small slack term here if optimality matters.
                        let key = "\(alightTime.stopId)|\(state.transitLegCount + 1)"
                        if let bestArrival = bestArrivalByStopAndLegCount[key],
                           bestArrival <= alightTime.arrivalSeconds {
                            continue
                        }
                        bestArrivalByStopAndLegCount[key] = alightTime.arrivalSeconds
                    }

                    let transitLeg = scheduledTransitLeg(
                        sequence: state.legs.count,
                        trip: trip,
                        route: route,
                        boardTime: boardTime,
                        alightTime: alightTime,
                        boardStop: boardStop,
                        alightStop: alightStop,
                        context: context
                    )
                    var visitedStopIds = state.visitedStopIds
                    visitedStopIds.insert(alightTime.stopId)

                    queue.push(JourneyState(
                        stopId: alightTime.stopId,
                        readySeconds: alightTime.arrivalSeconds,
                        legs: state.legs + [transitLeg],
                        transitLegCount: state.transitLegCount + 1,
                        visitedStopIds: visitedStopIds
                    ))
                }
            }

            for transfer in context.transfersByFromStopId[state.stopId, default: []] {
                guard !state.visitedStopIds.contains(transfer.toStopId),
                      let fromStop = context.stopsById[transfer.fromStopId],
                      let toStop = context.stopsById[transfer.toStopId] else {
                    continue
                }
                let distance = routeSearchDistanceMeters(from: fromStop.location, to: toStop.location)
                let seconds = max(
                    transfer.minimumTransferSeconds ?? 0,
                    walkingSeconds(for: distance) + transferBufferSeconds
                )
                let arrivalSeconds = state.readySeconds + seconds
                let key = "\(transfer.toStopId)|\(state.transitLegCount)"
                if let bestArrival = bestArrivalByStopAndLegCount[key],
                   bestArrival <= arrivalSeconds {
                    continue
                }
                bestArrivalByStopAndLegCount[key] = arrivalSeconds

                let transferLeg = walkingLeg(
                    id: "transfer-\(transfer.fromStopId)-\(transfer.toStopId)",
                    from: fromStop.location,
                    to: toStop.location,
                    departureSeconds: state.readySeconds,
                    arrivalSeconds: arrivalSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: distance,
                    instruction: "Walk to \(toStop.name)"
                )
                var visitedStopIds = state.visitedStopIds
                visitedStopIds.insert(transfer.toStopId)
                queue.push(JourneyState(
                    stopId: transfer.toStopId,
                    readySeconds: arrivalSeconds,
                    legs: state.legs + [transferLeg],
                    transitLegCount: state.transitLegCount,
                    visitedStopIds: visitedStopIds
                ))
            }
        }

        return deduplicatedByTripSequence(
            candidates
                .filter { $0.legs.contains { $0.transportKind == .transit } }
                .map { ScheduledJourney(legs: justInTimeLeadingWalk($0.legs)) }
                .sorted { $0.arrivalTime < $1.arrivalTime }
        )
    }

    /// Collapses dead time before boarding by snapping any leading walking legs to
    /// abut the first transit departure (`arrival = board`, `departure = board − walk`).
    /// Without this an arrive-by plan's access walk starts at the search anchor (hours
    /// early); with it the plan reflects the real "leave by" time.
    func deduplicatedByTripSequence(_ candidates: [ScheduledJourney]) -> [ScheduledJourney] {
        var bestBySignature: [String: ScheduledJourney] = [:]
        var order: [String] = []

        for candidate in candidates {
            let signature = candidate.tripSignature
            guard let existing = bestBySignature[signature] else {
                bestBySignature[signature] = candidate
                order.append(signature)
                continue
            }
            if isMoreComfortable(candidate, than: existing) {
                bestBySignature[signature] = candidate
            }
        }

        return order.compactMap { bestBySignature[$0] }
    }

    /// Orders two journeys riding the same vehicles by rider comfort: earliest arrival,
    /// then latest departure (least waiting before the first bus), then least walking,
    /// then fewest legs (a same-stop change beats a walk transfer), then the latest
    /// first-vehicle alight — i.e. stay aboard the first bus to the last shared stop
    /// rather than hopping off at the earliest one.
    func isMoreComfortable(_ lhs: ScheduledJourney, than rhs: ScheduledJourney) -> Bool {
        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        if lhs.departureTime != rhs.departureTime { return lhs.departureTime > rhs.departureTime }
        if lhs.totalWalkingMeters != rhs.totalWalkingMeters {
            return lhs.totalWalkingMeters < rhs.totalWalkingMeters
        }
        if lhs.legs.count != rhs.legs.count { return lhs.legs.count < rhs.legs.count }
        return lhs.firstTransitAlightTime > rhs.firstTransitAlightTime
    }

    func brokenConnectionPenalty(for legs: [RoutePlan.Leg]) -> Int {
        var penalty = 0
        for index in legs.indices.dropLast() {
            let current = legs[index]
            let next = legs[index + 1]
            guard current.transportKind == .transit,
                  next.transportKind == .transit,
                  let arrival = current.realtimeArrivalTime ?? current.scheduledArrivalTime ?? current.arrivalTime,
                  let nextDeparture = next.realtimeDepartureTime ?? next.scheduledDepartureTime ?? next.departureTime,
                  arrival.addingTimeInterval(Double(transferBufferSeconds)) > nextDeparture else {
                continue
            }
            penalty += 50000
        }
        return penalty
    }

    /// Ranking cost for an enriched candidate: arrival time plus a per-transfer
    /// penalty plus the live-data reliability penalty (cancelled/broken/no-realtime).
    /// Lower is better. This is what makes a slightly-later direct route outrank a
    /// faster multi-transfer one.
    func comfortCostSeconds(_ candidate: RouteCandidate) -> Double {
        candidate.arrivalTime.timeIntervalSinceReferenceDate
            + Double(candidate.transitLegCount * transferPenaltySeconds)
            + Double(candidate.penalty)
    }

    /// Pre-enrichment cost over scheduled data only (no live penalties known yet).
    func scheduledComfortCostSeconds(_ journey: ScheduledJourney) -> Double {
        journey.arrivalTime.timeIntervalSinceReferenceDate
            + Double(journey.transitLegCount * transferPenaltySeconds)
    }

    /// Arrive-by ranking: prefer the journey you can board **latest** (less waiting),
    /// among feasible ones, then fewer transfers, then earlier arrival. Cancelled /
    /// broken candidates (severe penalty) sink to the bottom.
    func departsLater(_ lhs: ScheduledJourney, _ rhs: ScheduledJourney) -> Bool {
        if lhs.firstTransitDeparture != rhs.firstTransitDeparture {
            return lhs.firstTransitDeparture > rhs.firstTransitDeparture
        }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        return lhs.arrivalTime < rhs.arrivalTime
    }

    func departsLater(_ lhs: RouteCandidate, _ rhs: RouteCandidate) -> Bool {
        let lhsSevere = lhs.penalty >= severePenaltyThreshold
        let rhsSevere = rhs.penalty >= severePenaltyThreshold
        if lhsSevere != rhsSevere {
            return !lhsSevere
        }
        if lhs.firstTransitDeparture != rhs.firstTransitDeparture {
            return lhs.firstTransitDeparture > rhs.firstTransitDeparture
        }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        return lhs.arrivalTime < rhs.arrivalTime
    }

    /// Door-to-door duration: last arrival minus the first leg's actual departure.
    /// Uses the journey's own start (not the search anchor), so arrive-by plans don't
    /// report the hours of phantom wait baked into the anchored `now`.
    func travelTime(for legs: [RoutePlan.Leg]) -> TimeInterval? {
        guard let start = legs.compactMap(\.departureTime).first,
              let end = legs.compactMap(\.arrivalTime).last else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    /// Stable per-itinerary identity from the transit trips and walk endpoints (never
    /// wall-clock), so a `.leaveNow` recalculation keeps the rider's selected option.
    func optionSignature(for legs: [RoutePlan.Leg]) -> String {
        legs.map { leg in
            switch leg.transportKind {
            case .transit:
                [
                    "t",
                    leg.tripId ?? leg.routeId ?? leg.id,
                    leg.originStopId ?? "",
                    leg.destinationStopId ?? "",
                    String(Int(leg.scheduledDepartureTime?.timeIntervalSince1970 ?? 0))
                ].joined(separator: ":")
            default:
                ["w", leg.origin.id, leg.destination.id].joined(separator: ":")
            }
        }.joined(separator: "-")
    }

    /// Removes journeys dominated on all three axes — a dominated journey boards its
    /// first transit leg no earlier, arrives no later, and uses no fewer transfers than
    /// another, with at least one of those strictly worse. Keeping the departure axis
    /// preserves distinct upcoming departures (which would collapse under an
    /// arrival/transfers-only frontier).
    func paretoFiltered<T>(
        _ items: [T],
        departure: (T) -> Date,
        arrival: (T) -> Date,
        transfers: (T) -> Int
    ) -> [T] {
        let keyed = items.map { (departure: departure($0), arrival: arrival($0), transfers: transfers($0), value: $0) }
        return keyed.enumerated()
            .filter { index, candidate in
                !keyed.enumerated().contains { otherIndex, other in
                    guard otherIndex != index else { return false }
                    let noWorse = other.departure >= candidate.departure
                        && other.arrival <= candidate.arrival
                        && other.transfers <= candidate.transfers
                    let strictlyBetter = other.departure > candidate.departure
                        || other.arrival < candidate.arrival
                        || other.transfers < candidate.transfers
                    return noWorse && strictlyBetter
                }
            }
            .map(\.element.value)
    }

    func nearestStops(
        to point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double,
        limit: Int
    ) -> [StopCandidate] {
        context.stopsById.values
            .compactMap { stop -> StopCandidate? in
                let distance = routeSearchDistanceMeters(from: point, to: stop.location)
                guard distance <= radiusMeters else { return nil }
                return StopCandidate(stop: stop, distanceMeters: distance)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map(\.self)
    }
}
