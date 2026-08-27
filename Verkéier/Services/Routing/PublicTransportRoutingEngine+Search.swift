import CoreLocation
import Foundation
import MapKit

extension PublicTransportRoutingEngine {
    nonisolated func enrichedDepartureProfile(
        _ candidates: [RouteCandidate],
        arriveBy: Bool,
        deadline: Date?,
        limit: Int
    ) -> [RouteCandidate] {
        guard limit > 0 else { return [] }
        let usable = candidates.contains(where: { $0.penalty < severePenaltyThreshold })
            ? candidates.filter { $0.penalty < severePenaltyThreshold }
            : candidates

        var bestByDeparture: [Int: RouteCandidate] = [:]
        for candidate in usable {
            let departure = Int(candidate.departureTime.timeIntervalSince1970.rounded())
            if let existing = bestByDeparture[departure] {
                if fastestCandidateRanksBefore(candidate, existing) {
                    bestByDeparture[departure] = candidate
                }
            } else {
                bestByDeparture[departure] = candidate
            }
        }
        let unique = Array(bestByDeparture.values)

        if arriveBy {
            let onTime = unique.filter { candidate in
                deadline.map { candidate.arrivalTime <= $0 } ?? true
            }
            return Array(onTime
                .sorted { $0.departureTime > $1.departureTime }
                .prefix(limit))
        }

        var result: [RouteCandidate] = []
        var threshold = unique.map(\.departureTime).min() ?? .distantFuture
        while result.count < limit {
            let remaining = unique.filter { $0.departureTime >= threshold }
            guard let best = remaining.min(by: { fastestCandidateRanksBefore($0, $1) }) else {
                break
            }
            result.append(best)
            threshold = best.departureTime.addingTimeInterval(1)
        }
        return result
    }

    private nonisolated func fastestCandidateRanksBefore(
        _ lhs: RouteCandidate,
        _ rhs: RouteCandidate
    ) -> Bool {
        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        if lhs.totalWalkingMeters != rhs.totalWalkingMeters {
            return lhs.totalWalkingMeters < rhs.totalWalkingMeters
        }
        if lhs.departureTime != rhs.departureTime { return lhs.departureTime > rhs.departureTime }
        return lhs.signature < rhs.signature
    }

    /// Builds direct vel’OH! alternatives. Bike stations are represented as
    /// ordinary journey nodes so the result can be combined with transit
    /// candidates by the same enrichment and presentation pipeline.
    nonisolated func bikeJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        stations: [BikeShareStation],
        context: RouteSearchContext,
        arriveByDeadlineSeconds: Int? = nil
    ) -> [ScheduledJourney] {
        let usable = stations.filter { $0.isOpen != false }
        guard usable.count >= 2 else { return [] }

        let candidates = usable.flatMap { pickup in
            usable.compactMap { dropoff -> ScheduledJourney? in
                guard pickup.id != dropoff.id else { return nil }

                let accessDistance = context.walkingDistanceMeters(from: origin, to: pickup.location)
                let bikeDistance = routeSearchDistanceMeters(from: pickup.location, to: dropoff.location)
                let egressDistance = context.walkingDistanceMeters(from: dropoff.location, to: destination)
                guard bikeDistance >= 100 else { return nil }

                let accessSeconds = walkingSeconds(for: accessDistance)
                let bikeSeconds = max(60, Int((bikeDistance / bikeSpeedMetersPerSecond).rounded(.up)))
                    + bikeUnlockSeconds
                let egressSeconds = walkingSeconds(for: egressDistance)
                let totalSeconds = accessSeconds + bikeSeconds + egressSeconds
                let accessStart = arriveByDeadlineSeconds.map { $0 - totalSeconds }
                    ?? context.currentSeconds
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
    nonisolated func mixedBikeJourneys(
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

    private nonisolated func bestBikeConnection(
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
                let accessDistance = context.walkingDistanceMeters(from: origin, to: pickup.location)
                let bikeDistance = routeSearchDistanceMeters(from: pickup.location, to: dropoff.location)
                let egressDistance = context.walkingDistanceMeters(from: dropoff.location, to: destination)
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

    private nonisolated func bikeAvailabilityWarning(
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

    nonisolated func isBikeShareJourney(_ journey: ScheduledJourney) -> Bool {
        journey.legs.contains { $0.transportKind == .bikeShare }
    }

    nonisolated func deduplicatedJourneys(_ candidates: [ScheduledJourney]) -> [ScheduledJourney] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.signature).inserted }
    }

    nonisolated func brokenConnectionPenalty(for legs: [RoutePlan.Leg]) -> Int {
        var penalty = 0
        let transitIndices = legs.indices.filter { legs[$0].transportKind == .transit }
        for pair in zip(transitIndices, transitIndices.dropFirst()) {
            guard let slack = transferSlackSeconds(
                fromTransitAt: pair.0,
                toTransitAt: pair.1,
                in: legs
            ), slack < Double(transferBufferSeconds) else { continue }
            penalty += 50_000
        }
        return penalty
    }

    /// Time left after completing the physical movement between consecutive rides.
    /// Safety padding is intentionally excluded so callers can compare it once against
    /// the active online/offline transfer buffer.
    nonisolated func transferSlackSeconds(
        fromTransitAt firstIndex: Int,
        toTransitAt secondIndex: Int,
        in legs: [RoutePlan.Leg]
    ) -> TimeInterval? {
        guard firstIndex < secondIndex,
              let arrival = effectiveArrivalTime(legs[firstIndex]),
              let departure = effectiveDepartureTime(legs[secondIndex]) else {
            return nil
        }

        let movementSeconds = legs[(firstIndex + 1) ..< secondIndex].reduce(0.0) { total, leg in
            if leg.transportKind == .walking {
                return total + physicalWalkingDuration(leg, fallback: 0)
            }
            guard let start = effectiveDepartureTime(leg),
                  let end = effectiveArrivalTime(leg) else { return total }
            return total + max(0, end.timeIntervalSince(start))
        }
        return departure.timeIntervalSince(arrival.addingTimeInterval(movementSeconds))
    }

    /// Ranking cost for an enriched candidate: arrival time plus a per-transfer
    /// penalty plus the live-data reliability penalty (cancelled/broken/no-realtime).
    /// Lower is better. This is what makes a slightly-later direct route outrank a
    /// faster multi-transfer one.
    nonisolated func comfortCostSeconds(_ candidate: RouteCandidate) -> Double {
        candidate.arrivalTime.timeIntervalSinceReferenceDate
            + Double(candidate.transitLegCount * transferPenaltySeconds)
            + Double(candidate.penalty)
    }

    /// Scheduled arrive-by ranking. Door-to-door departure includes the access walk,
    /// which is the rider-facing answer to "when do I need to leave?".
    nonisolated func arriveByRanksBefore(
        _ lhs: ScheduledJourney,
        _ rhs: ScheduledJourney,
        filters: RoutePlannerFilters
    ) -> Bool {
        if lhs.departureTime != rhs.departureTime {
            return lhs.departureTime > rhs.departureTime
        }
        if scheduledPreferenceRanksBefore(lhs, rhs, filters: filters) {
            return true
        }
        if scheduledPreferenceRanksBefore(rhs, lhs, filters: filters) {
            return false
        }
        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        return lhs.signature < rhs.signature
    }

    /// Final arrive-by ranking after realtime enrichment. Routes still predicted to
    /// meet the deadline always precede late ones; broken/cancelled connections sink.
    nonisolated func arriveByRanksBefore(
        _ lhs: RouteCandidate,
        _ rhs: RouteCandidate,
        deadline: Date,
        filters: RoutePlannerFilters
    ) -> Bool {
        let lhsSevere = lhs.penalty >= severePenaltyThreshold
        let rhsSevere = rhs.penalty >= severePenaltyThreshold
        if lhsSevere != rhsSevere { return rhsSevere }

        let lhsOnTime = lhs.arrivalTime <= deadline
        let rhsOnTime = rhs.arrivalTime <= deadline
        if lhsOnTime != rhsOnTime { return lhsOnTime }
        if !lhsOnTime {
            let lhsLateness = lhs.arrivalTime.timeIntervalSince(deadline)
            let rhsLateness = rhs.arrivalTime.timeIntervalSince(deadline)
            if lhsLateness != rhsLateness { return lhsLateness < rhsLateness }
        }

        if lhs.departureTime != rhs.departureTime {
            return lhs.departureTime > rhs.departureTime
        }
        if candidatePreferenceRanksBefore(lhs, rhs, filters: filters) {
            return true
        }
        if candidatePreferenceRanksBefore(rhs, lhs, filters: filters) {
            return false
        }
        if lhs.penalty != rhs.penalty { return lhs.penalty < rhs.penalty }
        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        return lhs.signature < rhs.signature
    }

    nonisolated func scheduledPreferenceRanksBefore(
        _ lhs: ScheduledJourney,
        _ rhs: ScheduledJourney,
        filters _: RoutePlannerFilters
    ) -> Bool {
        let lhsDuration = lhs.arrivalTime.timeIntervalSince(lhs.departureTime)
        let rhsDuration = rhs.arrivalTime.timeIntervalSince(rhs.departureTime)
        return lhsDuration < rhsDuration
    }

    nonisolated func candidatePreferenceRanksBefore(
        _ lhs: RouteCandidate,
        _ rhs: RouteCandidate,
        filters _: RoutePlannerFilters
    ) -> Bool {
        let lhsDuration = lhs.arrivalTime.timeIntervalSince(lhs.departureTime)
        let rhsDuration = rhs.arrivalTime.timeIntervalSince(rhs.departureTime)
        return lhsDuration < rhsDuration
    }

    /// Ordering for leave-now and depart-at searches. This deliberately mirrors the
    /// planner tabs: Fastest means earliest destination arrival, not the shortest
    /// elapsed duration or an implicit transfer-comfort score.
    nonisolated func scheduledRanksBefore(
        _ lhs: ScheduledJourney,
        _ rhs: ScheduledJourney,
        filters _: RoutePlannerFilters
    ) -> Bool {
        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        if lhs.totalWalkingMeters != rhs.totalWalkingMeters {
            return lhs.totalWalkingMeters < rhs.totalWalkingMeters
        }
        if lhs.departureTime != rhs.departureTime { return lhs.departureTime > rhs.departureTime }
        return lhs.signature < rhs.signature
    }

    nonisolated func candidateRanksBefore(
        _ lhs: RouteCandidate,
        _ rhs: RouteCandidate,
        filters _: RoutePlannerFilters
    ) -> Bool {
        let lhsSevere = lhs.penalty >= severePenaltyThreshold
        let rhsSevere = rhs.penalty >= severePenaltyThreshold
        if lhsSevere != rhsSevere { return !lhsSevere }

        if lhs.arrivalTime != rhs.arrivalTime { return lhs.arrivalTime < rhs.arrivalTime }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        if lhs.totalWalkingMeters != rhs.totalWalkingMeters {
            return lhs.totalWalkingMeters < rhs.totalWalkingMeters
        }
        if lhs.penalty != rhs.penalty { return lhs.penalty < rhs.penalty }
        if lhs.departureTime != rhs.departureTime { return lhs.departureTime > rhs.departureTime }
        return lhs.signature < rhs.signature
    }

    nonisolated func departsLater(_ lhs: ScheduledJourney, _ rhs: ScheduledJourney) -> Bool {
        if lhs.departureTime != rhs.departureTime {
            return lhs.departureTime > rhs.departureTime
        }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        return lhs.arrivalTime < rhs.arrivalTime
    }

    nonisolated func departsLater(_ lhs: RouteCandidate, _ rhs: RouteCandidate) -> Bool {
        let lhsSevere = lhs.penalty >= severePenaltyThreshold
        let rhsSevere = rhs.penalty >= severePenaltyThreshold
        if lhsSevere != rhsSevere {
            return !lhsSevere
        }
        if lhs.departureTime != rhs.departureTime {
            return lhs.departureTime > rhs.departureTime
        }
        if lhs.transitLegCount != rhs.transitLegCount {
            return lhs.transitLegCount < rhs.transitLegCount
        }
        return lhs.arrivalTime < rhs.arrivalTime
    }

    /// Door-to-door duration: last arrival minus the first leg's actual departure.
    /// Uses the journey's own start (not the search anchor), so arrive-by plans don't
    /// report the hours of phantom wait baked into the anchored `now`.
    nonisolated func travelTime(for legs: [RoutePlan.Leg]) -> TimeInterval? {
        guard let start = legs.compactMap(\.departureTime).first,
              let end = legs.compactMap(\.arrivalTime).last else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    /// Stable per-itinerary identity from the transit trips and walk endpoints (never
    /// wall-clock), so a `.leaveNow` recalculation keeps the rider's selected option.
    nonisolated func optionSignature(for legs: [RoutePlan.Leg]) -> String {
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

    nonisolated func nearestStops(
        to point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double,
        limit: Int
    ) -> [StopCandidate] {
        context.nearbyStops(to: point, radiusMeters: radiusMeters)
            .compactMap { stop -> StopCandidate? in
                let geometricDistance = routeSearchDistanceMeters(from: point, to: stop.location)
                guard geometricDistance <= radiusMeters else { return nil }
                let walkingDistance = context.walkingDistanceMeters(from: point, to: stop.location)
                guard walkingDistance <= radiusMeters else { return nil }
                return StopCandidate(stop: stop, distanceMeters: walkingDistance)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map(\.self)
    }
}
