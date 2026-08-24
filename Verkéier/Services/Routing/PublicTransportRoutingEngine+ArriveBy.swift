import Foundation

extension PublicTransportRoutingEngine {
    /// Searches the timetable in reverse from an arrival deadline. Unlike the old
    /// forward lookback, labels at an intermediate stop keep the latest feasible
    /// arrival, so later connecting journeys are not pruned by earlier ones.
    func arriveByJourneys(
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

        let originStopsById = Dictionary(uniqueKeysWithValues: originStops.map { ($0.stop.id, $0) })
        let earliestSearchSeconds = context.currentSeconds - searchHorizonSeconds
        var queue = ReverseJourneyPriorityQueue()

        for destinationCandidate in destinationStops {
            let egressWalkSeconds = walkingSeconds(for: destinationCandidate.distanceMeters)
            let latestAtStop = context.currentSeconds - egressWalkSeconds
            let egressLeg = walkingLeg(
                id: "egress-\(destinationCandidate.stop.id)",
                from: destinationCandidate.stop.location,
                to: destination,
                departureSeconds: latestAtStop,
                arrivalSeconds: context.currentSeconds,
                serviceStart: context.serviceStart,
                distanceMeters: destinationCandidate.distanceMeters,
                instruction: "Walk to \(destination.name ?? destinationCandidate.stop.name)"
            )
            queue.push(ReverseJourneyState(
                stopId: destinationCandidate.stop.id,
                latestSeconds: latestAtStop,
                legs: destinationCandidate.distanceMeters > minimumWalkLegMeters ? [egressLeg] : [],
                transitLegCount: 0,
                visitedStopIds: [destinationCandidate.stop.id],
                transferDeadlineSeconds: nil,
                transferWalkSeconds: 0,
                transferMinimumSeconds: 0
            ))
        }

        var candidatesByTripSignature: [String: ScheduledJourney] = [:]
        var candidateDepartureCutoffSeconds: Int?
        var bestDepartureByStopAndLegCount: [RouteSearchLabelKey: Int] = [:]
        var expansionCount = 0

        while let state = queue.popMax(), expansionCount < 5000 {
            if Task.isCancelled { return [] }
            expansionCount += 1
            guard state.latestSeconds >= earliestSearchSeconds else { continue }
            if let cutoff = candidateDepartureCutoffSeconds,
               state.latestSeconds < cutoff {
                // The queue is ordered latest-first and an origin access walk can only
                // move departure earlier. Nothing remaining can enter the top result
                // window once its optimistic departure is below the current cutoff.
                break
            }

            if let originCandidate = originStopsById[state.stopId],
               state.transitLegCount > 0,
               state.transferDeadlineSeconds == nil {
                let accessWalkSeconds = walkingSeconds(for: originCandidate.distanceMeters)
                let departureSeconds = state.latestSeconds - accessWalkSeconds
                if departureSeconds >= earliestSearchSeconds {
                    let accessLeg = walkingLeg(
                        id: "access-\(originCandidate.stop.id)",
                        from: origin,
                        to: originCandidate.stop.location,
                        departureSeconds: departureSeconds,
                        arrivalSeconds: state.latestSeconds,
                        serviceStart: context.serviceStart,
                        distanceMeters: originCandidate.distanceMeters,
                        instruction: "Walk to \(originCandidate.stop.name)"
                    )
                    let completeLegs = originCandidate.distanceMeters > minimumWalkLegMeters
                        ? [accessLeg] + state.legs
                        : state.legs
                    let candidate = ScheduledJourney(legs: retimedWalkingLegs(completeLegs))
                    let signature = candidate.tripSignature
                    if let existing = candidatesByTripSignature[signature] {
                        if isBetterArriveByRepresentative(candidate, than: existing) {
                            candidatesByTripSignature[signature] = candidate
                        }
                    } else {
                        candidatesByTripSignature[signature] = candidate
                    }
                    if candidatesByTripSignature.count >= evaluatedCandidateLimit {
                        let rankedDepartures = candidatesByTripSignature.values
                            .map { Int($0.departureTime.timeIntervalSince(context.serviceStart).rounded()) }
                            .sorted(by: >)
                        candidateDepartureCutoffSeconds = rankedDepartures[evaluatedCandidateLimit - 1]
                        continue
                    }
                }
            }

            guard state.transitLegCount < maximumTransitLegs else { continue }

            // A same-stop change needs one safety buffer. A walking transfer state
            // already incorporated that buffer across the whole physical walk.
            let latestAlightSeconds = state.transferDeadlineSeconds == nil && state.transitLegCount > 0
                ? state.latestSeconds - max(
                    transferBufferSeconds,
                    context.sameStopMinimumTransferSecondsByStopId[state.stopId, default: 0]
                )
                : state.latestSeconds
            let references = context.alightReferencesByStopId[state.stopId, default: []]
            let firstReferenceIndex = firstAlightingReferenceIndex(
                atOrBefore: latestAlightSeconds,
                references: references,
                context: context
            )
            for reference in references.dropFirst(firstReferenceIndex) {
                let trip = context.activeTrips[reference.tripIndex]
                let alightTime = trip.stopTimes[reference.stopTimeIndex]
                guard alightTime.arrivalSeconds >= earliestSearchSeconds else { break }
                guard alightTime.dropOffType != "1",
                      alightTime.arrivalSeconds <= latestAlightSeconds,
                      let alightStop = context.stopsById[alightTime.stopId],
                      let route = context.routesById[trip.routeId] else {
                    continue
                }

                for upstreamIndex in trip.stopTimes.indices[..<reference.stopTimeIndex].reversed() {
                    let boardTime = trip.stopTimes[upstreamIndex]
                    guard boardTime.pickupType != "1",
                          boardTime.departureSeconds < alightTime.arrivalSeconds,
                          !state.visitedStopIds.contains(boardTime.stopId),
                          let boardStop = context.stopsById[boardTime.stopId] else {
                        continue
                    }

                    let isOriginStop = originStopsById[boardTime.stopId] != nil
                    if !isOriginStop {
                        let key = RouteSearchLabelKey(
                            stopId: boardTime.stopId,
                            transitLegCount: state.transitLegCount + 1
                        )
                        if let bestDeparture = bestDepartureByStopAndLegCount[key],
                           bestDeparture >= boardTime.departureSeconds {
                            continue
                        }
                        bestDepartureByStopAndLegCount[key] = boardTime.departureSeconds
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
                    visitedStopIds.insert(boardTime.stopId)
                    queue.push(ReverseJourneyState(
                        stopId: boardTime.stopId,
                        latestSeconds: boardTime.departureSeconds,
                        legs: [transitLeg] + state.legs,
                        transitLegCount: state.transitLegCount + 1,
                        visitedStopIds: visitedStopIds,
                        transferDeadlineSeconds: nil,
                        transferWalkSeconds: 0,
                        transferMinimumSeconds: 0
                    ))
                }
            }

            guard state.transitLegCount > 0 else { continue }
            for transfer in context.transfersByToStopId[state.stopId, default: []] {
                guard !state.visitedStopIds.contains(transfer.fromStopId),
                      let fromStop = context.stopsById[transfer.fromStopId],
                      let toStop = context.stopsById[transfer.toStopId] else {
                    continue
                }

                let distance = routeSearchDistanceMeters(from: fromStop.location, to: toStop.location)
                let edgeWalkSeconds = walkingSeconds(for: distance)
                let transferDeadlineSeconds = state.transferDeadlineSeconds ?? state.latestSeconds
                let cumulativeWalkSeconds = state.transferWalkSeconds + edgeWalkSeconds
                let cumulativeMinimumSeconds = max(
                    state.transferMinimumSeconds,
                    transfer.minimumTransferSeconds ?? 0
                )
                let requiredSeconds = max(
                    cumulativeWalkSeconds + transferBufferSeconds,
                    cumulativeMinimumSeconds
                )
                let latestAtFromStop = transferDeadlineSeconds - requiredSeconds
                guard latestAtFromStop >= earliestSearchSeconds else { continue }

                let key = RouteSearchLabelKey(
                    stopId: transfer.fromStopId,
                    transitLegCount: state.transitLegCount
                )
                if let bestDeparture = bestDepartureByStopAndLegCount[key],
                   bestDeparture >= latestAtFromStop {
                    continue
                }
                bestDepartureByStopAndLegCount[key] = latestAtFromStop

                let edgeLeg = walkingLeg(
                    id: "transfer-\(transfer.fromStopId)-\(transfer.toStopId)",
                    from: fromStop.location,
                    to: toStop.location,
                    departureSeconds: latestAtFromStop,
                    arrivalSeconds: latestAtFromStop + edgeWalkSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: distance,
                    instruction: "Walk to \(toStop.name)"
                )
                var legs = state.legs
                if state.transferDeadlineSeconds != nil,
                   let nextWalk = legs.first,
                   nextWalk.transportKind == .walking {
                    legs[0] = mergedWalkingLeg(edgeLeg, nextWalk)
                } else {
                    legs.insert(edgeLeg, at: 0)
                }
                var visitedStopIds = state.visitedStopIds
                visitedStopIds.insert(transfer.fromStopId)
                queue.push(ReverseJourneyState(
                    stopId: transfer.fromStopId,
                    latestSeconds: latestAtFromStop,
                    legs: legs,
                    transitLegCount: state.transitLegCount,
                    visitedStopIds: visitedStopIds,
                    transferDeadlineSeconds: transferDeadlineSeconds,
                    transferWalkSeconds: cumulativeWalkSeconds,
                    transferMinimumSeconds: cumulativeMinimumSeconds
                ))
            }
        }

        return candidatesByTripSignature.values
            .filter { $0.legs.contains { $0.transportKind == .transit } }
            .map { ScheduledJourney(legs: retimedWalkingLegs($0.legs)) }
            .sorted { $0.departureTime > $1.departureTime }
    }

    func firstAlightingReferenceIndex(
        atOrBefore seconds: Int,
        references: [TripStopReference],
        context: RouteSearchContext
    ) -> Int {
        var lowerBound = 0
        var upperBound = references.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            let reference = references[middle]
            let arrival = context.activeTrips[reference.tripIndex]
                .stopTimes[reference.stopTimeIndex].arrivalSeconds
            if arrival > seconds {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }
}
