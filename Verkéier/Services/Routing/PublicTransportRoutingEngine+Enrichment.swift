import CoreLocation
import Foundation
import MapKit

/// A race that returns to the caller without waiting for an uncooperative
/// provider task. The provider task is cancelled, but its eventual completion
/// is not part of the route-calculation critical path.
private actor RoutingTimeoutGate<Value: Sendable> {
    private var finished = false
    private var value: Value?
    private var continuation: CheckedContinuation<Value?, Never>?

    func finish(_ value: Value?) {
        guard !finished else { return }
        finished = true
        self.value = value
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        }
    }

    func wait() async -> Value? {
        if finished { return value }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private func routingValueWithin<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async -> T? {
    guard seconds > 0 else { return nil }

    let gate = RoutingTimeoutGate<T>()
    let work = Task { [gate] in
        do {
            await gate.finish(try await operation())
        } catch {
            await gate.finish(nil)
        }
    }
    let timeout = Task { [gate] in
        do {
            try await Task.sleep(for: .milliseconds(max(1, Int((seconds * 1_000).rounded()))))
            await gate.finish(nil)
        } catch {
            // The operation completed first or the parent calculation was cancelled.
        }
    }

    let result = await withTaskCancellationHandler(
        operation: { await gate.wait() },
        onCancel: {
            work.cancel()
            timeout.cancel()
            Task { await gate.finish(nil) }
        }
    )
    work.cancel()
    timeout.cancel()
    return result
}

extension PublicTransportRoutingEngine {
    nonisolated func justInTimeLeadingWalk(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        guard let firstTransitIndex = legs.firstIndex(where: { $0.transportKind == .transit }),
              firstTransitIndex > 0,
              let board = legs[firstTransitIndex].realtimeDepartureTime
              ?? legs[firstTransitIndex].scheduledDepartureTime
              ?? legs[firstTransitIndex].departureTime else {
            return legs
        }

        var result = legs
        var anchor = board
        for index in stride(from: firstTransitIndex - 1, through: 0, by: -1) {
            let leg = result[index]
            guard leg.transportKind == .walking,
                  let departure = leg.departureTime,
                  let arrival = leg.arrivalTime else {
                break
            }
            let duration = physicalWalkingDuration(leg, fallback: arrival.timeIntervalSince(departure))
            let shiftedDeparture = anchor.addingTimeInterval(-duration)
            result[index] = copy(
                leg,
                departureTime: shiftedDeparture,
                arrivalTime: anchor,
                scheduledDepartureTime: shiftedDeparture,
                scheduledArrivalTime: anchor
            )
            anchor = shiftedDeparture
        }
        return result
    }

    /// Walking is synthetic routing data, so keep it physically attached to the
    /// preceding leg after realtime enrichment. Any remaining time before the next
    /// vehicle is then presented as waiting at the boarding stop, not as walking.
    nonisolated func retimedWalkingLegs(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result = justInTimeLeadingWalk(normalizedWalkingLegs(legs))
        guard result.count > 1 else { return result }

        for index in result.indices.dropFirst() where result[index].transportKind == .walking {
            guard let previousArrival = effectiveArrivalTime(result[index - 1]) else { continue }
            let duration = physicalWalkingDuration(result[index], fallback: 0)
            let arrival = previousArrival.addingTimeInterval(duration)
            result[index] = copy(
                result[index],
                departureTime: previousArrival,
                arrivalTime: arrival,
                scheduledDepartureTime: previousArrival,
                scheduledArrivalTime: arrival
            )
        }
        return result
    }

    nonisolated func normalizedWalkingLegs(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result: [RoutePlan.Leg] = []
        result.reserveCapacity(legs.count)
        for leg in legs {
            if leg.transportKind == .walking,
               let previous = result.last,
               previous.transportKind == .walking {
                result[result.count - 1] = mergedWalkingLeg(previous, leg)
            } else {
                result.append(leg)
            }
        }
        return result
    }

    nonisolated func mergedWalkingLeg(_ first: RoutePlan.Leg, _ second: RoutePlan.Leg) -> RoutePlan.Leg {
        var coordinates = first.mapCoordinates
        if coordinates.isEmpty {
            coordinates = [RouteMapCoordinate(first.origin), RouteMapCoordinate(first.destination)]
        }
        let secondCoordinates = second.mapCoordinates.isEmpty
            ? [RouteMapCoordinate(second.origin), RouteMapCoordinate(second.destination)]
            : second.mapCoordinates
        if coordinates.last == secondCoordinates.first {
            coordinates.append(contentsOf: secondCoordinates.dropFirst())
        } else {
            coordinates.append(contentsOf: secondCoordinates)
        }

        let departure = effectiveDepartureTime(first) ?? first.departureTime
        let firstDuration = physicalWalkingDuration(first, fallback: 0)
        let secondDuration = physicalWalkingDuration(second, fallback: 0)
        let arrival = departure?.addingTimeInterval(firstDuration + secondDuration)
        return RoutePlan.Leg(
            id: "\(first.id)-\(second.id)",
            mode: .walking,
            instruction: second.instruction,
            transportKind: .walking,
            origin: first.origin,
            destination: second.destination,
            departureTime: departure,
            arrivalTime: arrival,
            scheduledDepartureTime: departure,
            scheduledArrivalTime: arrival,
            distanceMeters: (first.distanceMeters ?? 0) + (second.distanceMeters ?? 0),
            mapCoordinates: coordinates,
            roadRoutingHint: .walking,
            liveStatus: .scheduled
        )
    }

    nonisolated func physicalWalkingDuration(_ leg: RoutePlan.Leg, fallback: TimeInterval) -> TimeInterval {
        guard let distance = leg.distanceMeters else { return max(0, fallback) }
        return TimeInterval(walkingSeconds(for: distance))
    }

    nonisolated func effectiveDepartureTime(_ leg: RoutePlan.Leg) -> Date? {
        leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
    }

    nonisolated func effectiveArrivalTime(_ leg: RoutePlan.Leg) -> Date? {
        leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
    }

    func enrich(
        _ candidates: [ScheduledJourney],
        context _: RouteSearchContext,
        forceRealtimeRefresh: Bool = false
    ) async throws -> (candidates: [RouteCandidate], boardsByStopId: [String: [Departure]]) {
        // Offline mode plans purely on the static schedule — no ATP fetch, and no
        // no-realtime penalty (which would otherwise flag every leg as unverified).
        guard !offlineMode else {
            return (
                try await enrichedCandidatesConcurrently(
                    candidates,
                    boardsByStopId: [:]
                ),
                [:]
            )
        }

        let kernel = RouteSearchKernel(engine: self)
        let stopIds = kernel.realtimeStopIDs(for: candidates)

        let boardsByStopId = try await departureBoardsByStopId(
            stopIds: stopIds,
            forceRefresh: forceRealtimeRefresh,
            allowNetwork: forceRealtimeRefresh
        )
        return (
            try await enrichedCandidatesConcurrently(
                candidates,
                boardsByStopId: boardsByStopId
            ),
            boardsByStopId
        )
    }

    /// Applies one immutable realtime snapshot using a bounded worker pool. Each
    /// worker keeps its own result buffer; the caller restores input order after
    /// all workers finish so network completion order cannot affect ranking.
    func enrichedCandidatesConcurrently(
        _ candidates: [ScheduledJourney],
        boardsByStopId: [String: [Departure]]
    ) async throws -> [RouteCandidate] {
        guard !candidates.isEmpty else { return [] }

        let workerCount = min(concurrency.cpuWorkerLimit, candidates.count)
        let kernel = RouteSearchKernel(engine: self)
        var ordered = Array<RouteCandidate?>(repeating: nil, count: candidates.count)

        try await withThrowingTaskGroup(of: [(Int, RouteCandidate)].self) { group in
            for worker in 0 ..< workerCount {
                group.addTask { @concurrent in
                    var results: [(Int, RouteCandidate)] = []
                    var index = worker
                    while index < candidates.count {
                        try Task.checkCancellation()
                        guard let candidate = kernel.enrichedCandidates(
                            [candidates[index]],
                            boardsByStopId: boardsByStopId
                        ).first else {
                            index += workerCount
                            continue
                        }
                        results.append((index, candidate))
                        index += workerCount
                    }
                    return results
                }
            }

            for try await batch in group {
                for (index, candidate) in batch {
                    ordered[index] = candidate
                }
            }
        }

        return ordered.compactMap { $0 }
    }

    /// Applies the live snapshot already collected for a route-calculation pass.
    /// A missing departure board is deliberately not a failure: that leg remains
    /// scheduled so services without ATP coverage still appear in the results.
    nonisolated func enrichedCandidates(
        _ candidates: [ScheduledJourney],
        boardsByStopId: [String: [Departure]]
    ) -> [RouteCandidate] {
        var enriched: [RouteCandidate] = []
        enriched.reserveCapacity(candidates.count)

        for candidate in candidates {
            var legs: [RoutePlan.Leg] = []
            legs.reserveCapacity(candidate.legs.count)
            var penalty = 0

            for leg in candidate.legs {
                guard leg.transportKind == .transit,
                      let originStopId = leg.originStopId else {
                    legs.append(leg)
                    continue
                }

                let departures = boardsByStopId[originStopId, default: []]
                if let matchedDeparture = matchedDeparture(for: leg, in: departures) {
                    let enrichedLeg = liveLeg(leg, departure: matchedDeparture)
                    penalty += matchedDeparture.isCancelled ? 100_000 : 0
                    penalty += matchedDeparture.realtimeDeparture == nil ? 60 : 0
                    legs.append(enrichedLeg)
                } else {
                    penalty += 60
                    legs.append(leg)
                }
            }

            let retimedLegs = retimedWalkingLegs(legs)
            penalty += brokenConnectionPenalty(for: retimedLegs)
            enriched.append(RouteCandidate(legs: retimedLegs, penalty: penalty))
        }

        return enriched
    }

    /// Replans only the suffix after a live cancellation or a now-impossible
    /// transfer. This preserves a catchable incoming vehicle and lets the standard
    /// timetable search choose the next departure from the transfer station.
    func repairedCandidates(
        from candidates: [RouteCandidate],
        origin: LocationPoint,
        destination: LocationPoint,
        context: RouteSearchContext,
        filters: RoutePlannerFilters,
        boardsByStopId: [String: [Departure]]
    ) async throws -> [RealtimeRouteRepair] {
        guard !offlineMode else { return [] }

        let kernel = RouteSearchKernel(engine: self)
        let jobs = try await routeCalculationConcurrent {
            try Task.checkCancellation()
            return try kernel.repairJobs(
                from: candidates,
                origin: origin,
                destination: destination,
                context: context
            )
        }
        guard !jobs.isEmpty else { return [] }

        let enriched = try await enrichedCandidatesConcurrently(
            jobs.map(\.journey),
            boardsByStopId: boardsByStopId
        )

        var bestRepairBySignature: [String: RealtimeRouteRepair] = [:]
        for (job, repaired) in zip(jobs, enriched) {
            try Task.checkCancellation()
            guard firstUnusableTransitIndex(in: repaired.legs) == nil,
                  matchesModePreference(repaired, filters: filters) else {
                continue
            }

            let repair = RealtimeRouteRepair(
                originalSignature: job.originalSignature,
                candidate: repaired
            )
            if let existing = bestRepairBySignature[repaired.signature] {
                if comfortCostSeconds(repaired) < comfortCostSeconds(existing.candidate) {
                    bestRepairBySignature[repaired.signature] = repair
                }
            } else {
                bestRepairBySignature[repaired.signature] = repair
            }
        }

        return bestRepairBySignature.keys.sorted().compactMap {
            bestRepairBySignature[$0]
        }
    }

    nonisolated func firstUnusableTransitIndex(in legs: [RoutePlan.Leg]) -> Int? {
        let transitIndices = legs.indices.filter { legs[$0].transportKind == .transit }
        for index in transitIndices where legs[index].liveStatus == .cancelled {
            return index
        }
        for pair in zip(transitIndices, transitIndices.dropFirst()) {
            guard let slack = transferSlackSeconds(
                fromTransitAt: pair.0,
                toTransitAt: pair.1,
                in: legs
            ), slack < Double(transferBufferSeconds) else {
                continue
            }
            return pair.1
        }
        return nil
    }

    nonisolated func repairStart(
        for candidate: RouteCandidate,
        brokenTransitIndex: Int,
        origin: LocationPoint,
        context: RouteSearchContext
    ) -> (origin: LocationPoint, context: RouteSearchContext, prefix: [RoutePlan.Leg], prefixTransitLegCount: Int)? {
        let transitIndices = candidate.legs.indices.filter {
            candidate.legs[$0].transportKind == .transit
        }
        guard let firstTransitIndex = transitIndices.first else { return nil }

        // A cancelled first ride has no viable prefix; search again from the rider's
        // actual origin rather than forcing them to walk to its cancelled platform.
        if brokenTransitIndex == firstTransitIndex,
           candidate.legs[brokenTransitIndex].liveStatus == .cancelled {
            return (origin, context, [], 0)
        }

        guard brokenTransitIndex > 0,
              let previousTransitIndex = transitIndices.last(where: { $0 < brokenTransitIndex }) else {
            return nil
        }
        let prefix = retimedWalkingLegs(Array(candidate.legs[..<brokenTransitIndex]))
        guard let physicalArrival = prefix.last.flatMap(effectiveArrivalTime) else {
            return nil
        }

        let previousTransit = candidate.legs[previousTransitIndex]
        let brokenTransit = candidate.legs[brokenTransitIndex]
        let sameStopMinimum = previousTransit.destinationStopId == brokenTransit.originStopId
            ? context.sameStopMinimumTransferSecondsByStopId[brokenTransit.originStopId ?? "", default: 0]
            : 0
        let readySeconds = Int(
            physicalArrival
                .addingTimeInterval(TimeInterval(max(transferBufferSeconds, sameStopMinimum)))
                .timeIntervalSince(context.serviceStart)
                .rounded(.up)
        )

        return (
            brokenTransit.origin,
            context.rebased(at: readySeconds),
            prefix,
            prefix.reduce(0) { $0 + ($1.transportKind == .transit ? 1 : 0) }
        )
    }

    nonisolated func matchesModePreference(_ candidate: RouteCandidate, filters: RoutePlannerFilters) -> Bool {
        guard let preferredMode = filters.modePreference.transportMode else { return true }
        return candidate.legs.contains {
            $0.transportKind == .transit && $0.mode == preferredMode
        }
    }

    func departureBoardsByStopId(
        stopIds: Set<String>,
        forceRefresh: Bool = false,
        allowNetwork: Bool = true
    ) async throws -> [String: [Departure]] {
        let requestedStopIds = stopIds.sorted()
        guard !requestedStopIds.isEmpty else { return [:] }

        let fetchedAt = Date.now
        var boardsByStopId: [String: [Departure]] = [:]
        var missingStopIds: [String] = []
        for stopId in requestedStopIds {
            if !forceRefresh,
               let cached = cachedDepartureBoards[stopId],
               fetchedAt.timeIntervalSince(cached.fetchedAt) < realtimeBoardCacheLifetime {
                boardsByStopId[stopId] = cached.departures
            } else {
                missingStopIds.append(stopId)
            }
        }

        // The initial planner pass is cards-first: use whatever ATP snapshot is
        // already cached and let missing boards remain schedule-only. A user
        // initiated refresh is the explicit opt-in for network enrichment.
        guard allowNetwork else { return boardsByStopId }

        let gtfsService = gtfsService
        let atpClient = atpClient
        let deadline = Date.now.addingTimeInterval(realtimeBoardBudgetSeconds)
        for batchStart in stride(
            from: 0,
            to: missingStopIds.count,
            by: concurrency.realtimeBoardLimit
        ) {
            try Task.checkCancellation()
            let remainingSeconds = deadline.timeIntervalSinceNow
            guard remainingSeconds > 0 else { break }
            let batchEnd = min(batchStart + concurrency.realtimeBoardLimit, missingStopIds.count)
            let batch = Array(missingStopIds[batchStart..<batchEnd])
            let fetchedBoards = try await withThrowingTaskGroup(of: (String, [Departure]).self) { group in
                for stopId in batch {
                    group.addTask { @concurrent in
                        try Task.checkCancellation()
                        let platformIds = await gtfsService.stop(id: stopId)?.platformIds ?? [stopId]
                        let departures = await routingValueWithin(
                            seconds: max(0.001, remainingSeconds),
                            operation: {
                                try await atpClient.departureBoards(stopIds: platformIds)
                            }
                        ) ?? []
                        return (stopId, departures)
                    }
                }

                var results: [(String, [Departure])] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            for (stopId, departures) in fetchedBoards {
                boardsByStopId[stopId] = departures
                cachedDepartureBoards[stopId] = CachedDepartureBoard(
                    departures: departures,
                    fetchedAt: fetchedAt
                )
            }
        }

        return boardsByStopId
    }

    /// Builds final options through a bounded worker pool. Candidate geometry is
    /// already either schedule-only or road-refined by the calculation pipeline.
    func routeOptions(
        from candidates: [RouteCandidate],
        origin: LocationPoint,
        destination: LocationPoint,
        context: RouteSearchContext
    ) async throws -> [RouteOption] {
        guard !candidates.isEmpty else { return [] }

        let workerCount = min(concurrency.roadRouteLimit, candidates.count)
        var ordered = Array<RouteOption?>(repeating: nil, count: candidates.count)

        try await withThrowingTaskGroup(of: [(Int, RouteOption?)].self) { group in
            for worker in 0 ..< workerCount {
                group.addTask { @concurrent in
                    var results: [(Int, RouteOption?)] = []
                    var index = worker
                    while index < candidates.count {
                        try Task.checkCancellation()
                        let option = await self.routeOption(
                            from: candidates[index],
                            origin: origin,
                            destination: destination,
                            context: context
                        )
                        try Task.checkCancellation()
                        results.append((index, option))
                        index += workerCount
                    }
                    return results
                }
            }

            for try await batch in group {
                for (index, option) in batch {
                    ordered[index] = option
                }
            }
        }

        var seenOptionIDs: Set<String> = []
        var sawBikeShare = false
        return ordered.compactMap { $0 }.filter { option in
            seenOptionIDs.insert(option.id).inserted
        }.filter { option in
            guard option.usesBikeShare else { return true }
            guard !sawBikeShare else { return false }
            sawBikeShare = true
            return true
        }
    }

    /// Resolves the endpoint walks before timetable search. The candidate set is
    /// intentionally small (the nearest origin stops and destination matches),
    /// while transfer walks are resolved lazily for the much smaller candidate
    /// set after the timetable search.
    func contextWithWalkingDistances(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        bikeStations: [BikeShareStation]
    ) async -> RouteSearchContext {
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

        var keys = Set<RoadRouteCacheKey>()
        for stop in originStops {
            keys.insert(RoadRouteCacheKey(
                origin: RouteMapCoordinate(origin),
                destination: RouteMapCoordinate(stop.stop.location),
                transport: .walking
            ))
        }
        for stop in destinationStops {
            keys.insert(RoadRouteCacheKey(
                origin: RouteMapCoordinate(stop.stop.location),
                destination: RouteMapCoordinate(destination),
                transport: .walking
            ))
        }

        // Bike-share stations are also walking endpoints. Limit these to the
        // closest stations so optional bike routing cannot turn one calculation
        // into a large batch of pedestrian directions requests.
        let nearbyBikeStations = bikeStations
            .filter { $0.isOpen != false }
            .sorted {
                routeSearchDistanceMeters(from: origin, to: $0.location)
                    < routeSearchDistanceMeters(from: origin, to: $1.location)
            }
            .prefix(6)
        for station in nearbyBikeStations {
            keys.insert(RoadRouteCacheKey(
                origin: RouteMapCoordinate(origin),
                destination: RouteMapCoordinate(station.location),
                transport: .walking
            ))
        }
        for station in nearbyBikeStations {
            keys.insert(RoadRouteCacheKey(
                origin: RouteMapCoordinate(station.location),
                destination: RouteMapCoordinate(destination),
                transport: .walking
            ))
        }

        return context.withWalkingDistances(await resolvedRoadDistances(for: keys))
    }

    /// Resolves a bounded batch of road routes while preserving the existing
    /// fast-fallback behavior when MapKit is unavailable or slow.
    func resolvedRoadDistances(for keys: Set<RoadRouteCacheKey>) async -> [RoadRouteCacheKey: Double] {
        let walkingKeys = keys.filter { $0.transport == .walking }
        guard !walkingKeys.isEmpty else { return [:] }

        let deadline = Date.now.addingTimeInterval(roadGeometryBudgetSeconds)
        let orderedKeys = walkingKeys.sorted {
            if $0.originLatitude != $1.originLatitude {
                return $0.originLatitude < $1.originLatitude
            }
            if $0.originLongitude != $1.originLongitude {
                return $0.originLongitude < $1.originLongitude
            }
            if $0.destinationLatitude != $1.destinationLatitude {
                return $0.destinationLatitude < $1.destinationLatitude
            }
            return $0.destinationLongitude < $1.destinationLongitude
        }
        let workerCount = min(concurrency.roadRouteLimit, orderedKeys.count)
        var distances: [RoadRouteCacheKey: Double] = [:]

        await withTaskGroup(of: [(RoadRouteCacheKey, Double?)].self) { group in
            for worker in 0 ..< workerCount {
                group.addTask { @concurrent in
                    var results: [(RoadRouteCacheKey, Double?)] = []
                    var index = worker
                    while index < orderedKeys.count {
                        if Task.isCancelled { break }
                        let key = orderedKeys[index]
                        let remainingSeconds = deadline.timeIntervalSinceNow
                        guard remainingSeconds > 0 else { break }
                        let route = await routingValueWithin(
                            seconds: remainingSeconds,
                            operation: { [self] in
                                await roadRoute(for: key)
                            }
                        ) ?? nil
                        results.append((key, route?.distanceMeters))
                        index += workerCount
                    }
                    return results
                }
            }

            for await batch in group {
                for (key, distance) in batch {
                    if let distance {
                        distances[key] = distance
                    }
                }
            }
        }
        return distances
    }

    /// Applies road distances to the candidate walks before the final ranking.
    /// This means a longer pedestrian path can change both the displayed ETA and
    /// which connection is considered catchable.
    func roadRoutedCandidates(_ candidates: [RouteCandidate]) async throws -> [RouteCandidate] {
        guard !candidates.isEmpty else { return [] }

        let workerCount = min(concurrency.roadRouteLimit, candidates.count)
        var ordered = Array<RouteCandidate?>(repeating: nil, count: candidates.count)
        try await withThrowingTaskGroup(of: [(Int, RouteCandidate)].self) { group in
            for worker in 0 ..< workerCount {
                group.addTask { @concurrent in
                    var results: [(Int, RouteCandidate)] = []
                    var index = worker
                    while index < candidates.count {
                        try Task.checkCancellation()
                        let routedLegs = await self.legsWithRoadRoutedSegments(candidates[index].legs)
                        let legs = self.retimedWalkingLegs(routedLegs)
                        results.append((
                            index,
                            RouteCandidate(
                                legs: legs,
                                penalty: candidates[index].penalty + self.brokenConnectionPenalty(for: legs)
                            )
                        ))
                        index += workerCount
                    }
                    return results
                }
            }

            for try await batch in group {
                for (index, candidate) in batch {
                    ordered[index] = candidate
                }
            }
        }
        return ordered.compactMap { $0 }
    }

    /// Collapses journeys that ride the **same ordered sequence of vehicle trips** into
    /// one. Two itineraries on the identical buses that just change at a different shared
    /// stop (or board the same trip from a different nearby access stop) are one journey
    /// to the rider, not five — so they keyed on stop IDs before and showed up repeatedly.
    /// Keeps the most comfortable representative per trip sequence.
    func routeOption(
        from candidate: RouteCandidate,
        origin: LocationPoint,
        destination: LocationPoint,
        context _: RouteSearchContext
    ) async -> RouteOption? {
        let legs = legsWithTransferWarnings(retimedWalkingLegs(candidate.legs))
        guard legs.contains(where: {
            $0.transportKind == .transit || $0.transportKind == .bikeShare
        }) else {
            return nil
        }
        // GTFS shapes and stop coordinates are sufficient for the initial overlay.
        // Exact road geometry is applied only by the background force-refresh.
        let routedLegs = legs

        let optionID = "gtfs-option-\(origin.id)-\(destination.id)-\(optionSignature(for: routedLegs))"
        let plan = RoutePlan(
            id: optionID,
            origin: origin,
            destination: destination,
            expectedTravelTime: travelTime(for: routedLegs),
            distanceMeters: routedLegs.compactMap(\.distanceMeters).reduce(0, +),
            legs: routedLegs,
            dataSource: .gtfs
        )
        return RouteOption(id: optionID, plan: plan, mapOverlay: overlay(from: routedLegs))
    }

    func legsWithRoadRoutedSegments(_ legs: [RoutePlan.Leg]) async -> [RoutePlan.Leg] {
        var result = legs
        for index in result.indices {
            guard let transport = RoadRouteTransport(result[index].roadRoutingHint) else {
                continue
            }

            let coordinates = result[index].mapCoordinates.isEmpty
                ? [RouteMapCoordinate(result[index].origin), RouteMapCoordinate(result[index].destination)]
                : result[index].mapCoordinates
            guard let roadRoute = await routingValueWithin(
                seconds: roadGeometryBudgetSeconds,
                operation: { [self] in
                    await roadRoute(connecting: coordinates, transport: transport)
                }
            ) ?? nil else {
                continue
            }
            let isWalking = result[index].transportKind == .walking
            result[index] = copy(
                result[index],
                distanceMeters: isWalking ? roadRoute.distanceMeters : nil,
                mapCoordinates: roadRoute.coordinates
            )
        }
        return result
    }

    func roadCoordinates(
        connecting coordinates: [RouteMapCoordinate],
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        guard coordinates.count >= 2 else { return nil }

        guard !Task.isCancelled,
              let origin = coordinates.first,
              let destination = coordinates.last else {
            return nil
        }

        // A shaped bus leg may contain hundreds of stop/shape points. One
        // endpoint-to-endpoint request is enough for optional refinement; asking
        // MapKit to route every adjacent pair made route calculation scale with
        // the number of intermediate stops.
        return await roadCoordinates(
            from: origin,
            to: destination,
            transport: transport
        )
    }

    func roadRoute(
        connecting coordinates: [RouteMapCoordinate],
        transport: RoadRouteTransport
    ) async -> RoadRoute? {
        guard coordinates.count >= 2 else { return nil }

        guard !Task.isCancelled,
              let origin = coordinates.first,
              let destination = coordinates.last else {
            return nil
        }

        return await roadRoute(
            from: origin,
            to: destination,
            transport: transport
        )
    }

    func roadCoordinates(
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }

    func roadRoute(
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) async -> RoadRoute? {
        let key = RoadRouteCacheKey(
            origin: origin,
            destination: destination,
            transport: transport
        )
        if let cachedRoute = roadRouteCache[key] {
            return cachedRoute
        }

        let route = await roadRouteProvider.roadRoute(
            from: LocationPoint(
                latitude: origin.latitude,
                longitude: origin.longitude
            ),
            to: LocationPoint(
                latitude: destination.latitude,
                longitude: destination.longitude
            ),
            transport: transport
        )
        let acceptedRoute = route.flatMap {
            acceptableRoadRoute($0, from: origin, to: destination, transport: transport)
        }
        // The dictionary value is optional so failed/refused geometry is cached
        // too; assigning the inner nil directly would remove the key.
        roadRouteCache[key] = .some(acceptedRoute)
        return acceptedRoute
    }

    func roadRoute(for key: RoadRouteCacheKey) async -> RoadRoute? {
        await roadRoute(
            from: RouteMapCoordinate(
                latitude: key.originLatitude,
                longitude: key.originLongitude
            ),
            to: RouteMapCoordinate(
                latitude: key.destinationLatitude,
                longitude: key.destinationLongitude
            ),
            transport: key.transport
        )
    }

    nonisolated func acceptableRoadRoute(
        _ route: RoadRoute,
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) -> RoadRoute? {
        guard route.coordinates.count >= 2,
              route.distanceMeters.isFinite,
              route.distanceMeters >= 0 else {
            return nil
        }

        let directDistance = routeSearchDistanceMeters(
            from: LocationPoint(latitude: origin.latitude, longitude: origin.longitude),
            to: LocationPoint(latitude: destination.latitude, longitude: destination.longitude)
        )
        guard directDistance > 0 else { return route }
        guard route.distanceMeters > 0 else { return nil }

        let routedDistance = polylineDistanceMeters(route.coordinates)
        let maximumDistanceRatio = transport == .automobile ? 2.2 : 2.8
        let maximumExtraDistance = transport == .automobile ? 600.0 : 900.0
        let allowedDistance = max(
            directDistance * maximumDistanceRatio,
            directDistance + maximumExtraDistance
        )
        guard routedDistance <= allowedDistance,
              route.distanceMeters <= allowedDistance else { return nil }

        let maximumDetourDistance = max(directDistance * 1.25, 350.0)
        guard route.coordinates.allSatisfy({
            distanceFromRouteCorridorMeters(point: $0, origin: origin, destination: destination)
                <= maximumDetourDistance
        }) else {
            return nil
        }

        return route
    }

    nonisolated func acceptableRoadCoordinates(
        _ coordinates: [RouteMapCoordinate],
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) -> [RouteMapCoordinate]? {
        let distance = polylineDistanceMeters(coordinates)
        guard let route = acceptableRoadRoute(
            RoadRoute(coordinates: coordinates, distanceMeters: distance),
            from: origin,
            to: destination,
            transport: transport
        ) else {
            return nil
        }
        return route.coordinates
    }

    nonisolated func polylineDistanceMeters(_ coordinates: [RouteMapCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + routeSearchDistanceMeters(
                from: LocationPoint(latitude: pair.0.latitude, longitude: pair.0.longitude),
                to: LocationPoint(latitude: pair.1.latitude, longitude: pair.1.longitude)
            )
        }
    }

    nonisolated func distanceFromRouteCorridorMeters(
        point: RouteMapCoordinate,
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate
    ) -> Double {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let routeDistance = originLocation.distance(from: destinationLocation)
        guard routeDistance > 0 else {
            return pointLocation.distance(from: originLocation)
        }

        let t = max(0, min(1, projectedFraction(
            point: point,
            origin: origin,
            destination: destination
        )))
        let interpolated = CLLocation(
            latitude: origin.latitude + (destination.latitude - origin.latitude) * t,
            longitude: origin.longitude + (destination.longitude - origin.longitude) * t
        )
        return pointLocation.distance(from: interpolated)
    }

    nonisolated func projectedFraction(
        point: RouteMapCoordinate,
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate
    ) -> Double {
        let originLatitude = origin.latitude * .pi / 180
        let longitudeScale = cos(originLatitude)
        let routeX = (destination.longitude - origin.longitude) * longitudeScale
        let routeY = destination.latitude - origin.latitude
        let pointX = (point.longitude - origin.longitude) * longitudeScale
        let pointY = point.latitude - origin.latitude
        let denominator = routeX * routeX + routeY * routeY
        guard denominator > 0 else { return 0 }
        return (pointX * routeX + pointY * routeY) / denominator
    }

    nonisolated func matchedDeparture(for leg: RoutePlan.Leg, in departures: [Departure]) -> Departure? {
        let scheduledDeparture = leg.scheduledDepartureTime ?? leg.departureTime
        return departures
            .filter { departure in
                guard routeMatches(departure: departure, leg: leg) else { return false }
                guard let scheduledDeparture,
                      let boardDeparture = departure.scheduledDeparture else {
                    return true
                }
                return abs(boardDeparture.timeIntervalSince(scheduledDeparture)) <= 20 * 60
            }
            .min { lhs, rhs in
                guard let scheduledDeparture else { return lhs.lineName < rhs.lineName }
                let lhsDelta = abs((lhs.scheduledDeparture ?? .distantFuture).timeIntervalSince(scheduledDeparture))
                let rhsDelta = abs((rhs.scheduledDeparture ?? .distantFuture).timeIntervalSince(scheduledDeparture))
                return lhsDelta < rhsDelta
            }
    }

    nonisolated func routeMatches(departure: Departure, leg: RoutePlan.Leg) -> Bool {
        if let routeId = leg.routeId,
           departure.routeId?.caseInsensitiveCompare(routeId) == .orderedSame {
            return true
        }

        if let routeName = leg.routeName,
           departure.lineName.caseInsensitiveCompare(routeName) == .orderedSame {
            return true
        }

        return false
    }

    nonisolated func liveLeg(_ leg: RoutePlan.Leg, departure: Departure) -> RoutePlan.Leg {
        let delay = departure.delayMinutes
        let realtimeDeparture = departure.realtimeDeparture
        let realtimeArrival = delay.map { minutes in
            (leg.scheduledArrivalTime ?? leg.arrivalTime)?.addingTimeInterval(Double(minutes * 60))
        } ?? nil
        let liveStatus: RouteLegLiveStatus = if departure.isCancelled {
            .cancelled
        } else if let delay, delay > 0 {
            .delayed
        } else if realtimeDeparture != nil {
            .live
        } else {
            .unknown
        }

        return copy(
            leg,
            departureTime: realtimeDeparture ?? leg.departureTime,
            arrivalTime: realtimeArrival ?? leg.arrivalTime,
            realtimeDepartureTime: realtimeDeparture,
            realtimeArrivalTime: realtimeArrival,
            platform: departure.platform,
            delayMinutes: delay,
            liveStatus: liveStatus
        )
    }

    nonisolated func legsWithTransferWarnings(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result = legs
        let transitIndices = result.indices.filter { result[$0].transportKind == .transit }
        for pair in zip(transitIndices, transitIndices.dropFirst()) {
            guard let slack = transferSlackSeconds(
                fromTransitAt: pair.0,
                toTransitAt: pair.1,
                in: result
            ) else { continue }
            guard slack <= Double(tightTransferThresholdSeconds) else { continue }

            let warning = if slack < Double(transferBufferSeconds) {
                "Connection miss"
            } else {
                "Tight connection — \(max(1, Int(slack / 60))) min to change"
            }
            // The warning belongs to the ride being boarded so the timeline displays
            // it at that boarding place, including when a walking leg sits between rides.
            result[pair.1] = copy(result[pair.1], transferWarning: warning)
        }

        return result
    }
}
