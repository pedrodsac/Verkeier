import CoreLocation
import Foundation
import HeapModule
import MapKit

extension PublicTransportRoutingEngine {
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
