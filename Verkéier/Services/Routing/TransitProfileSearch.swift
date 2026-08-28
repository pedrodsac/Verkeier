import Foundation

/// An integer-indexed, service-day view of the timetable used by the profile
/// search. Trips with the same route and stop sequence share a pattern. Trips
/// that overtake one another are split into separate patterns, which keeps a
/// binary search for the first catchable trip correct at every stop.
nonisolated struct TransitSearchIndex: Sendable {
    let stopIDs: [String]
    let stopIndexByID: [String: Int]
    let patterns: [TransitRoutePattern]
    let patternReferencesByStopIndex: [[TransitPatternStopReference]]
    let footpathsByStopIndex: [[IndexedTransitFootpath]]

    init(
        stops: [GTFSTimetableStopEntry],
        trips: [GTFSTimetableTripEntry],
        transfersByFromStopId: [String: [GTFSTimetableTransferEntry]]
    ) {
        let indexedStopIDs = stops.map(\.id)
        let indexedStopsByID = Dictionary(
            uniqueKeysWithValues: indexedStopIDs.enumerated().map { ($1, $0) }
        )
        stopIDs = indexedStopIDs
        stopIndexByID = indexedStopsByID

        var tripsByKey: [TransitPatternKey: [Int]] = [:]
        for tripIndex in trips.indices {
            let trip = trips[tripIndex]
            guard trip.stopTimes.count >= 2,
                  trip.stopTimes.allSatisfy({ indexedStopsByID[$0.stopId] != nil }) else {
                continue
            }
            tripsByKey[
                TransitPatternKey(routeID: trip.routeId, stopIDs: trip.stopTimes.map(\.stopId)),
                default: []
            ].append(tripIndex)
        }

        var builtPatterns: [TransitRoutePattern] = []
        for key in tripsByKey.keys.sorted(by: { $0.stableKey < $1.stableKey }) {
            let orderedTrips = tripsByKey[key, default: []].sorted {
                let lhs = trips[$0].stopTimes.first?.departureSeconds ?? .max
                let rhs = trips[$1].stopTimes.first?.departureSeconds ?? .max
                if lhs != rhs { return lhs < rhs }
                return trips[$0].id < trips[$1].id
            }
            var nonOvertakingGroups: [[Int]] = []
            for tripIndex in orderedTrips {
                if let groupIndex = nonOvertakingGroups.firstIndex(where: { group in
                    guard let previousTripIndex = group.last else { return true }
                    return Self.doesNotOvertake(
                        previous: trips[previousTripIndex],
                        next: trips[tripIndex]
                    )
                }) {
                    nonOvertakingGroups[groupIndex].append(tripIndex)
                } else {
                    nonOvertakingGroups.append([tripIndex])
                }
            }

            let stopIndices = key.stopIDs.compactMap { indexedStopsByID[$0] }
            builtPatterns.append(contentsOf: nonOvertakingGroups.map {
                TransitRoutePattern(
                    routeID: key.routeID,
                    stopIndices: stopIndices,
                    tripIndices: $0
                )
            })
        }
        patterns = builtPatterns

        var references = Array(
            repeating: [TransitPatternStopReference](),
            count: indexedStopIDs.count
        )
        for patternIndex in builtPatterns.indices {
            for stopPosition in builtPatterns[patternIndex].stopIndices.indices.dropLast() {
                let stopIndex = builtPatterns[patternIndex].stopIndices[stopPosition]
                references[stopIndex].append(
                    TransitPatternStopReference(
                        patternIndex: patternIndex,
                        stopPosition: stopPosition
                    )
                )
            }
        }
        patternReferencesByStopIndex = references

        var footpaths = Array(repeating: [IndexedTransitFootpath](), count: indexedStopIDs.count)
        for (fromStopID, transfers) in transfersByFromStopId {
            guard let fromStopIndex = indexedStopsByID[fromStopID] else { continue }
            let fromStop = stops[fromStopIndex]
            for transfer in transfers where transfer.toStopId != fromStopID {
                guard let toStopIndex = indexedStopsByID[transfer.toStopId] else { continue }
                let toStop = stops[toStopIndex]
                footpaths[fromStopIndex].append(
                    IndexedTransitFootpath(
                        toStopIndex: toStopIndex,
                        distanceMeters: routeSearchDistanceMeters(
                            from: fromStop.location,
                            to: toStop.location
                        ),
                        minimumTransferSeconds: transfer.minimumTransferSeconds ?? 0
                    )
                )
            }
        }
        footpathsByStopIndex = footpaths
    }

    private static func doesNotOvertake(
        previous: GTFSTimetableTripEntry,
        next: GTFSTimetableTripEntry
    ) -> Bool {
        zip(previous.stopTimes, next.stopTimes).allSatisfy { lhs, rhs in
            lhs.arrivalSeconds <= rhs.arrivalSeconds
                && lhs.departureSeconds <= rhs.departureSeconds
        }
    }
}

private nonisolated struct TransitPatternKey: Hashable, Sendable {
    let routeID: String
    let stopIDs: [String]

    var stableKey: String {
        ([routeID] + stopIDs).joined(separator: "\u{1F}")
    }
}

nonisolated struct TransitRoutePattern: Sendable {
    let routeID: String
    let stopIndices: [Int]
    let tripIndices: [Int]
}

nonisolated struct TransitPatternStopReference: Sendable {
    let patternIndex: Int
    let stopPosition: Int
}

nonisolated struct IndexedTransitFootpath: Sendable {
    let toStopIndex: Int
    let distanceMeters: Double
    let minimumTransferSeconds: Int
}

private nonisolated struct RaptorLabel: Sendable {
    let arrivalSeconds: Int
    let walkingMeters: Double
    let accessWalkingSeconds: Int
    let doorDepartureSeconds: Int?
    let minimumBoardingSeconds: Int
    let nodeIndex: Int
}

private nonisolated enum RaptorPredecessor: Sendable {
    case source(
        candidate: StopCandidate,
        departureSeconds: Int,
        arrivalSeconds: Int
    )
    case transit(
        parentNodeIndex: Int,
        tripIndex: Int,
        boardPosition: Int,
        alightPosition: Int
    )
    case footpath(
        parentNodeIndex: Int,
        fromStopIndex: Int,
        toStopIndex: Int,
        departureSeconds: Int,
        arrivalSeconds: Int,
        distanceMeters: Double
    )
}

private nonisolated struct RaptorDestinationLabel: Sendable {
    let label: RaptorLabel
    let destinationCandidate: StopCandidate
    let arrivalSeconds: Int
    let transitLegCount: Int
    let totalWalkingMeters: Double
}

extension PublicTransportRoutingEngine {
    /// Produces the departure/arrival profile consumed by the planner. The
    /// earliest-arrival query is repeated only for actual profile breakpoints:
    /// after publishing one journey the next query starts one second after that
    /// journey's just-in-time leave-origin value.
    nonisolated func profileScheduledJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        arriveBy: Bool,
        filters: RoutePlannerFilters,
        includeLiveReserves: Bool,
        page: RouteSearchPage = .initial,
        candidateLimit: Int = 10
    ) -> [ScheduledJourney] {
        let windowStepSeconds = 90 * 60
        let maximumWindowSeconds = 6 * 60 * 60

        if case let .later(_, requestedLimit) = page {
            let limit = min(max(0, requestedLimit), candidateLimit)
            guard limit > 0 else { return [] }
            var selected: [ScheduledJourney] = []
            var windowEndSeconds = context.currentSeconds + windowStepSeconds
            for windowSeconds in stride(
                from: windowStepSeconds,
                through: maximumWindowSeconds,
                by: windowStepSeconds
            ) {
                if Task.isCancelled { return [] }
                windowEndSeconds = context.currentSeconds + windowSeconds
                selected = departureProfile(
                    from: origin,
                    to: destination,
                    context: context,
                    filters: filters,
                    requestedDepartureSeconds: context.currentSeconds + 1,
                    departureWindowEndSeconds: windowEndSeconds,
                    limit: limit,
                    maximumTransitLegCount: maximumTransitLegs
                )
                if selected.count >= limit { break }
            }
            guard includeLiveReserves else { return selected }
            let reserves = directPatternReserves(
                from: origin,
                to: destination,
                context: context,
                filters: filters,
                requestedDepartureSeconds: context.currentSeconds + 1,
                departureWindowEndSeconds: windowEndSeconds,
                arriveByDeadlineSeconds: nil,
                limit: 5
            )
            return boundedWorkingProfile(
                selected + reserves,
                descending: false,
                limit: min(candidateLimit, limit + 5),
                filters: filters
            )
        }

        if case let .earlier(_, requestedLimit) = page {
            let limit = min(max(0, requestedLimit), candidateLimit)
            guard limit > 0 else { return [] }
            var selected: [ScheduledJourney] = []
            var processedEvents: Set<Int> = []
            let latestSeconds = context.currentSeconds - 1
            let earliestLimit = context.currentSeconds - maximumWindowSeconds
            let departureEvents = originDepartureEvents(
                from: origin,
                context: context,
                filters: filters,
                earliestSeconds: earliestLimit,
                latestSeconds: latestSeconds
            )
            for windowSeconds in stride(
                from: windowStepSeconds,
                through: maximumWindowSeconds,
                by: windowStepSeconds
            ) {
                if Task.isCancelled { return [] }
                let startSeconds = max(earliestLimit, context.currentSeconds - windowSeconds)
                for departureEvent in departureEvents
                    where departureEvent >= startSeconds
                    && processedEvents.insert(departureEvent).inserted {
                    if Task.isCancelled { return [] }
                    guard let journey = earliestRaptorJourney(
                        from: origin,
                        to: destination,
                        context: context,
                        filters: filters,
                        requestedDepartureSeconds: departureEvent,
                        departureWindowEndSeconds: departureEvent,
                        maximumTransitLegCount: maximumTransitLegs
                    ), journey.departureTime
                        < context.serviceStart.addingTimeInterval(TimeInterval(context.currentSeconds)) else {
                        continue
                    }
                    if selected.contains(where: {
                        $0.departureTime > journey.departureTime
                            && $0.arrivalTime <= journey.arrivalTime
                    }) {
                        continue
                    }
                    selected.append(journey)
                    selected = uniqueJourneysByDoorDeparture(selected, descending: true)
                    if selected.count >= limit { break }
                }
                if selected.count >= limit { break }
            }
            guard includeLiveReserves else { return Array(selected.prefix(limit)) }
            let reserves = directPatternReserves(
                from: origin,
                to: destination,
                context: context,
                filters: filters,
                requestedDepartureSeconds: earliestLimit,
                departureWindowEndSeconds: latestSeconds,
                arriveByDeadlineSeconds: nil,
                limit: 5
            ).filter { $0.departureTime
                < context.serviceStart.addingTimeInterval(TimeInterval(context.currentSeconds)) }
            return boundedWorkingProfile(
                selected + reserves,
                descending: true,
                limit: min(candidateLimit, limit + 5),
                filters: filters
            )
        }

        if arriveBy {
            var selected: [ScheduledJourney] = []
            var processedEvents: Set<Int> = []
            let departureEvents = originDepartureEvents(
                from: origin,
                context: context,
                filters: filters,
                earliestSeconds: max(0, context.currentSeconds - maximumWindowSeconds),
                latestSeconds: context.currentSeconds
            )
            for windowSeconds in stride(
                from: windowStepSeconds,
                through: maximumWindowSeconds,
                by: windowStepSeconds
            ) {
                if Task.isCancelled { return [] }
                let startSeconds = max(0, context.currentSeconds - windowSeconds)
                for departureEvent in departureEvents
                    where departureEvent >= startSeconds
                    && processedEvents.insert(departureEvent).inserted {
                    if Task.isCancelled { return [] }
                    guard let journey = earliestRaptorJourney(
                        from: origin,
                        to: destination,
                        context: context,
                        filters: filters,
                        requestedDepartureSeconds: departureEvent,
                        departureWindowEndSeconds: departureEvent,
                        maximumTransitLegCount: maximumTransitLegs
                    ), Int(journey.arrivalTime.timeIntervalSince(context.serviceStart).rounded())
                        <= context.currentSeconds else {
                        continue
                    }
                    // A later departure that arrives no later dominates this one.
                    if selected.contains(where: {
                        $0.departureTime > journey.departureTime
                            && $0.arrivalTime <= journey.arrivalTime
                    }) {
                        continue
                    }
                    selected.append(journey)
                    selected = uniqueJourneysByDoorDeparture(selected, descending: true)
                    if selected.count >= 5 { break }
                }
                if selected.count >= 5 { break }
            }
            guard includeLiveReserves else {
                return Array(selected.prefix(candidateLimit))
            }
            let reserves = directPatternReserves(
                from: origin,
                to: destination,
                context: context,
                filters: filters,
                requestedDepartureSeconds: max(0, context.currentSeconds - maximumWindowSeconds),
                departureWindowEndSeconds: context.currentSeconds,
                arriveByDeadlineSeconds: context.currentSeconds,
                limit: 5
            )
            return boundedWorkingProfile(
                selected + reserves,
                descending: true,
                limit: candidateLimit,
                filters: filters
            )
        }

        var selected: [ScheduledJourney] = []
        var windowEndSeconds = context.currentSeconds + windowStepSeconds
        for windowSeconds in stride(
            from: windowStepSeconds,
            through: maximumWindowSeconds,
            by: windowStepSeconds
        ) {
            if Task.isCancelled { return [] }
            windowEndSeconds = context.currentSeconds + windowSeconds
            selected = departureProfile(
                from: origin,
                to: destination,
                context: context,
                filters: filters,
                requestedDepartureSeconds: context.currentSeconds,
                departureWindowEndSeconds: windowEndSeconds,
                limit: min(5, candidateLimit),
                maximumTransitLegCount: maximumTransitLegs
            )
            if selected.count >= 5 { break }
        }

        // Keep a small set of direct-trip fallbacks behind the five public
        // profile points. They are normally hidden by the faster journey at the
        // same departure opportunity, but can replace it when live data breaks
        // a connection. The combined working set remains bounded at ten.
        guard includeLiveReserves else {
            return uniqueJourneysByDoorDeparture(selected, descending: false)
        }
        let directReserves = directPatternReserves(
            from: origin,
            to: destination,
            context: context,
            filters: filters,
            requestedDepartureSeconds: context.currentSeconds,
            departureWindowEndSeconds: windowEndSeconds,
            arriveByDeadlineSeconds: nil,
            limit: 5,
        )
        return boundedWorkingProfile(
            selected + directReserves,
            descending: false,
            limit: candidateLimit,
            filters: filters
        )
    }

    private nonisolated func departureProfile(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        filters: RoutePlannerFilters,
        requestedDepartureSeconds: Int,
        departureWindowEndSeconds: Int,
        limit: Int,
        maximumTransitLegCount: Int = 3
    ) -> [ScheduledJourney] {
        guard limit > 0 else { return [] }
        var threshold = requestedDepartureSeconds
        var journeys: [ScheduledJourney] = []
        var seenSignatures: Set<String> = []

        while journeys.count < limit, threshold <= departureWindowEndSeconds {
            if Task.isCancelled { return [] }
            guard let journey = earliestRaptorJourney(
                from: origin,
                to: destination,
                context: context,
                filters: filters,
                requestedDepartureSeconds: threshold,
                departureWindowEndSeconds: departureWindowEndSeconds,
                maximumTransitLegCount: maximumTransitLegCount
            ) else {
                break
            }

            let departureSeconds = Int(
                journey.departureTime.timeIntervalSince(context.serviceStart).rounded()
            )
            guard departureSeconds >= threshold,
                  departureSeconds <= departureWindowEndSeconds else {
                break
            }
            if seenSignatures.insert(journey.signature).inserted {
                journeys.append(journey)
            }
            threshold = departureSeconds + 1
        }
        return journeys
    }

    private nonisolated func earliestRaptorJourney(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        filters: RoutePlannerFilters,
        requestedDepartureSeconds: Int,
        departureWindowEndSeconds: Int,
        maximumTransitLegCount: Int
    ) -> ScheduledJourney? {
        let originCandidates = nearestStops(
            to: origin,
            in: context,
            radiusMeters: accessRadiusMeters,
            limit: 8
        )
        let destinationCandidates = destinationStopMatches(
            for: destination,
            in: context,
            radiusMeters: destinationRadiusMeters
        )
        guard !originCandidates.isEmpty, !destinationCandidates.isEmpty else { return nil }

        let index = context.transitIndex
        let preferredMode = filters.modePreference.transportMode
        let stateCount = preferredMode == nil ? 1 : 2
        let maximumRounds = filters.preferAccessible
            ? min(2, maximumTransitLegCount)
            : maximumTransitLegCount
        let maximumJourneySeconds = departureWindowEndSeconds + searchHorizonSeconds
        let requiredTransferSeconds = filters.avoidTightTransfers
            ? max(transferBufferSeconds, tightTransferThresholdSeconds + 1)
            : transferBufferSeconds
        var nodes: [RaptorPredecessor] = []
        var previous = Array(
            repeating: Array<RaptorLabel?>(repeating: nil, count: index.stopIDs.count),
            count: stateCount
        )

        for candidate in originCandidates {
            guard let stopIndex = index.stopIndexByID[candidate.stop.id] else { continue }
            let walkSeconds = walkingSeconds(for: candidate.distanceMeters)
            if filters.preferAccessible, candidate.distanceMeters > 700 { continue }
            let nodeIndex = nodes.count
            nodes.append(.source(
                candidate: candidate,
                departureSeconds: requestedDepartureSeconds,
                arrivalSeconds: requestedDepartureSeconds + walkSeconds
            ))
            let label = RaptorLabel(
                arrivalSeconds: requestedDepartureSeconds + walkSeconds,
                walkingMeters: candidate.distanceMeters,
                accessWalkingSeconds: walkSeconds,
                doorDepartureSeconds: nil,
                minimumBoardingSeconds: 0,
                nodeIndex: nodeIndex
            )
            if isBetterRaptorLabel(label, than: previous[0][stopIndex]) {
                previous[0][stopIndex] = label
            }
        }

        let indexedDestinations: [(stopIndex: Int, candidate: StopCandidate)] = destinationCandidates
            .compactMap { candidate in
                index.stopIndexByID[candidate.stop.id].map { ($0, candidate) }
            }
        var bestDestination: RaptorDestinationLabel?

        for round in 1 ... maximumRounds {
            if Task.isCancelled { return nil }
            var current = Array(
                repeating: Array<RaptorLabel?>(repeating: nil, count: index.stopIDs.count),
                count: stateCount
            )

            for state in 0 ..< stateCount {
                for boardStopIndex in previous[state].indices {
                    guard let boardLabel = previous[state][boardStopIndex] else { continue }
                    let stopID = index.stopIDs[boardStopIndex]
                    let sameStopMinimum = context.sameStopMinimumTransferSecondsByStopId[stopID, default: 0]
                    let readySeconds = boardLabel.arrivalSeconds + (round == 1 ? 0 : max(
                        requiredTransferSeconds,
                        max(sameStopMinimum, boardLabel.minimumBoardingSeconds)
                    ))

                    for reference in index.patternReferencesByStopIndex[boardStopIndex] {
                        if Task.isCancelled { return nil }
                        let pattern = index.patterns[reference.patternIndex]
                        guard let route = context.routesById[pattern.routeID],
                              let tripIndex = firstCatchableTripIndex(
                                  in: pattern,
                                  at: reference.stopPosition,
                                  readySeconds: readySeconds,
                                  firstRound: round == 1,
                                  accessWalkingSeconds: boardLabel.accessWalkingSeconds,
                                  departureWindowEndSeconds: departureWindowEndSeconds,
                                  maximumJourneySeconds: maximumJourneySeconds,
                                  context: context
                              ) else {
                            continue
                        }
                        let trip = context.activeTrips[tripIndex]
                        let boardTime = trip.stopTimes[reference.stopPosition]
                        let usesPreferredMode = state == 1 || route.transportMode == preferredMode
                        let nextState = preferredMode == nil ? 0 : (usesPreferredMode ? 1 : 0)
                        let doorDepartureSeconds = boardLabel.doorDepartureSeconds
                            ?? (boardTime.departureSeconds - boardLabel.accessWalkingSeconds)

                        for alightPosition in trip.stopTimes.indices.dropFirst(reference.stopPosition + 1) {
                            let alightTime = trip.stopTimes[alightPosition]
                            guard alightTime.dropOffType != "1",
                                  alightTime.arrivalSeconds > boardTime.departureSeconds,
                                  alightTime.arrivalSeconds <= maximumJourneySeconds,
                                  let alightStopIndex = index.stopIndexByID[alightTime.stopId] else {
                                continue
                            }
                            let nodeIndex = nodes.count
                            let label = RaptorLabel(
                                arrivalSeconds: alightTime.arrivalSeconds,
                                walkingMeters: boardLabel.walkingMeters,
                                accessWalkingSeconds: boardLabel.accessWalkingSeconds,
                                doorDepartureSeconds: doorDepartureSeconds,
                                minimumBoardingSeconds: context
                                    .sameStopMinimumTransferSecondsByStopId[alightTime.stopId, default: 0],
                                nodeIndex: nodeIndex
                            )
                            guard isBetterRaptorLabel(label, than: current[nextState][alightStopIndex]) else {
                                continue
                            }
                            nodes.append(.transit(
                                parentNodeIndex: boardLabel.nodeIndex,
                                tripIndex: tripIndex,
                                boardPosition: reference.stopPosition,
                                alightPosition: alightPosition
                            ))
                            current[nextState][alightStopIndex] = label
                        }
                    }
                }
            }

            relaxProfileFootpaths(
                labels: &current,
                nodes: &nodes,
                index: index,
                context: context,
                preferAccessible: filters.preferAccessible
            )

            let destinationStates = preferredMode == nil ? [0] : [1]
            for state in destinationStates {
                for destinationMatch in indexedDestinations {
                    guard let label = current[state][destinationMatch.stopIndex],
                          label.doorDepartureSeconds != nil else { continue }
                    let totalWalking = label.walkingMeters + destinationMatch.candidate.distanceMeters
                    if filters.preferAccessible, totalWalking > 700 { continue }
                    let arrivalSeconds = label.arrivalSeconds
                        + walkingSeconds(for: destinationMatch.candidate.distanceMeters)
                    let destinationLabel = RaptorDestinationLabel(
                        label: label,
                        destinationCandidate: destinationMatch.candidate,
                        arrivalSeconds: arrivalSeconds,
                        transitLegCount: round,
                        totalWalkingMeters: totalWalking
                    )
                    if isBetterDestinationLabel(destinationLabel, than: bestDestination) {
                        bestDestination = destinationLabel
                    }
                }
            }
            previous = current
        }

        guard let bestDestination else { return nil }
        return reconstructedJourney(
            destinationLabel: bestDestination,
            nodes: nodes,
            origin: origin,
            destination: destination,
            context: context
        )
    }

    private nonisolated func firstCatchableTripIndex(
        in pattern: TransitRoutePattern,
        at stopPosition: Int,
        readySeconds: Int,
        firstRound: Bool,
        accessWalkingSeconds: Int,
        departureWindowEndSeconds: Int,
        maximumJourneySeconds: Int,
        context: RouteSearchContext
    ) -> Int? {
        var lower = 0
        var upper = pattern.tripIndices.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let trip = context.activeTrips[pattern.tripIndices[middle]]
            if trip.stopTimes[stopPosition].departureSeconds < readySeconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        for offset in lower ..< pattern.tripIndices.count {
            let tripIndex = pattern.tripIndices[offset]
            let stopTime = context.activeTrips[tripIndex].stopTimes[stopPosition]
            guard stopTime.departureSeconds <= maximumJourneySeconds else { break }
            if stopTime.pickupType == "1" { continue }
            if firstRound,
               stopTime.departureSeconds - accessWalkingSeconds > departureWindowEndSeconds {
                break
            }
            return tripIndex
        }
        return nil
    }

    private nonisolated func relaxProfileFootpaths(
        labels: inout [[RaptorLabel?]],
        nodes: inout [RaptorPredecessor],
        index: TransitSearchIndex,
        context: RouteSearchContext,
        preferAccessible: Bool
    ) {
        for state in labels.indices {
            var queue = labels[state].indices.filter { labels[state][$0] != nil }
            var cursor = 0
            while cursor < queue.count {
                if Task.isCancelled { return }
                let fromStopIndex = queue[cursor]
                cursor += 1
                guard let fromLabel = labels[state][fromStopIndex],
                      let fromStop = context.stopsById[index.stopIDs[fromStopIndex]] else {
                    continue
                }
                for footpath in index.footpathsByStopIndex[fromStopIndex] {
                    guard let toStop = context.stopsById[index.stopIDs[footpath.toStopIndex]] else {
                        continue
                    }
                    let distance = context.walkingDistanceMeters(
                        from: fromStop.location,
                        to: toStop.location
                    )
                    let walkingMeters = fromLabel.walkingMeters + distance
                    if preferAccessible, walkingMeters > 700 { continue }
                    let arrivalSeconds = fromLabel.arrivalSeconds + walkingSeconds(for: distance)
                    let nodeIndex = nodes.count
                    let label = RaptorLabel(
                        arrivalSeconds: arrivalSeconds,
                        walkingMeters: walkingMeters,
                        accessWalkingSeconds: fromLabel.accessWalkingSeconds,
                        doorDepartureSeconds: fromLabel.doorDepartureSeconds,
                        minimumBoardingSeconds: max(
                            fromLabel.minimumBoardingSeconds,
                            footpath.minimumTransferSeconds
                        ),
                        nodeIndex: nodeIndex
                    )
                    guard isBetterRaptorLabel(label, than: labels[state][footpath.toStopIndex]) else {
                        continue
                    }
                    nodes.append(.footpath(
                        parentNodeIndex: fromLabel.nodeIndex,
                        fromStopIndex: fromStopIndex,
                        toStopIndex: footpath.toStopIndex,
                        departureSeconds: fromLabel.arrivalSeconds,
                        arrivalSeconds: arrivalSeconds,
                        distanceMeters: distance
                    ))
                    labels[state][footpath.toStopIndex] = label
                    queue.append(footpath.toStopIndex)
                }
            }
        }
    }

    private nonisolated func reconstructedJourney(
        destinationLabel: RaptorDestinationLabel,
        nodes: [RaptorPredecessor],
        origin: LocationPoint,
        destination: LocationPoint,
        context: RouteSearchContext
    ) -> ScheduledJourney? {
        var chain: [RaptorPredecessor] = []
        var nodeIndex: Int? = destinationLabel.label.nodeIndex
        while let currentIndex = nodeIndex, nodes.indices.contains(currentIndex) {
            let node = nodes[currentIndex]
            chain.append(node)
            switch node {
            case .source:
                nodeIndex = nil
            case let .transit(parentNodeIndex, _, _, _),
                 let .footpath(parentNodeIndex, _, _, _, _, _):
                nodeIndex = parentNodeIndex
            }
        }
        chain.reverse()

        var legs: [RoutePlan.Leg] = []
        for node in chain {
            switch node {
            case let .source(candidate, departureSeconds, arrivalSeconds):
                if candidate.distanceMeters > minimumWalkLegMeters {
                    legs.append(walkingLeg(
                        id: "access-\(candidate.stop.id)",
                        from: origin,
                        to: candidate.stop.location,
                        departureSeconds: departureSeconds,
                        arrivalSeconds: arrivalSeconds,
                        serviceStart: context.serviceStart,
                        distanceMeters: candidate.distanceMeters,
                        instruction: "Walk to \(candidate.stop.name)"
                    ))
                }
            case let .transit(_, tripIndex, boardPosition, alightPosition):
                let trip = context.activeTrips[tripIndex]
                let boardTime = trip.stopTimes[boardPosition]
                let alightTime = trip.stopTimes[alightPosition]
                guard let route = context.routesById[trip.routeId],
                      let boardStop = context.stopsById[boardTime.stopId],
                      let alightStop = context.stopsById[alightTime.stopId] else {
                    return nil
                }
                legs.append(scheduledTransitLeg(
                    sequence: legs.count,
                    trip: trip,
                    route: route,
                    boardTime: boardTime,
                    alightTime: alightTime,
                    boardStop: boardStop,
                    alightStop: alightStop,
                    context: context
                ))
            case let .footpath(_, fromStopIndex, toStopIndex, departureSeconds, arrivalSeconds, distance):
                guard let fromStop = context.stopsById[context.transitIndex.stopIDs[fromStopIndex]],
                      let toStop = context.stopsById[context.transitIndex.stopIDs[toStopIndex]] else {
                    return nil
                }
                legs.append(walkingLeg(
                    id: "transfer-\(fromStop.id)-\(toStop.id)",
                    from: fromStop.location,
                    to: toStop.location,
                    departureSeconds: departureSeconds,
                    arrivalSeconds: arrivalSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: distance,
                    instruction: "Walk to \(toStop.name)"
                ))
            }
        }

        if destinationLabel.destinationCandidate.distanceMeters > minimumWalkLegMeters,
           let lastStop = context.stopsById[destinationLabel.destinationCandidate.stop.id] {
            legs.append(walkingLeg(
                id: "egress-\(lastStop.id)",
                from: lastStop.location,
                to: destination,
                departureSeconds: destinationLabel.label.arrivalSeconds,
                arrivalSeconds: destinationLabel.arrivalSeconds,
                serviceStart: context.serviceStart,
                distanceMeters: destinationLabel.destinationCandidate.distanceMeters,
                instruction: "Walk to \(destination.name ?? lastStop.name)"
            ))
        }
        guard legs.contains(where: { $0.transportKind == .transit }) else { return nil }
        return ScheduledJourney(legs: normalizedWalkingLegs(justInTimeLeadingWalk(legs)))
    }

    private nonisolated func isBetterRaptorLabel(
        _ candidate: RaptorLabel,
        than existing: RaptorLabel?
    ) -> Bool {
        guard let existing else { return true }
        if candidate.arrivalSeconds != existing.arrivalSeconds {
            return candidate.arrivalSeconds < existing.arrivalSeconds
        }
        if candidate.walkingMeters != existing.walkingMeters {
            return candidate.walkingMeters < existing.walkingMeters
        }
        return (candidate.doorDepartureSeconds ?? .min) > (existing.doorDepartureSeconds ?? .min)
    }

    private nonisolated func isBetterDestinationLabel(
        _ candidate: RaptorDestinationLabel,
        than existing: RaptorDestinationLabel?
    ) -> Bool {
        guard let existing else { return true }
        if candidate.arrivalSeconds != existing.arrivalSeconds {
            return candidate.arrivalSeconds < existing.arrivalSeconds
        }
        if candidate.transitLegCount != existing.transitLegCount {
            return candidate.transitLegCount < existing.transitLegCount
        }
        if candidate.totalWalkingMeters != existing.totalWalkingMeters {
            return candidate.totalWalkingMeters < existing.totalWalkingMeters
        }
        return (candidate.label.doorDepartureSeconds ?? .min)
            > (existing.label.doorDepartureSeconds ?? .min)
    }

    /// Effective leave-origin timestamps reachable from the eight access stops.
    /// Arrive-by scans these events backwards and runs only exact-opportunity
    /// queries, avoiding the old 128-query forward sweep on frequent corridors.
    private nonisolated func originDepartureEvents(
        from origin: LocationPoint,
        context: RouteSearchContext,
        filters: RoutePlannerFilters,
        earliestSeconds: Int,
        latestSeconds: Int
    ) -> [Int] {
        let index = context.transitIndex
        let origins = nearestStops(
            to: origin,
            in: context,
            radiusMeters: accessRadiusMeters,
            limit: 8
        )
        var events: Set<Int> = []
        for originCandidate in origins {
            if filters.preferAccessible, originCandidate.distanceMeters > 700 { continue }
            guard let stopIndex = index.stopIndexByID[originCandidate.stop.id] else { continue }
            let accessSeconds = walkingSeconds(for: originCandidate.distanceMeters)
            for reference in index.patternReferencesByStopIndex[stopIndex] {
                let pattern = index.patterns[reference.patternIndex]
                guard let route = context.routesById[pattern.routeID],
                      filters.modePreference.transportMode.map({ $0 == route.transportMode }) ?? true else {
                    continue
                }
                for tripIndex in pattern.tripIndices {
                    let stopTime = context.activeTrips[tripIndex].stopTimes[reference.stopPosition]
                    guard stopTime.pickupType != "1" else { continue }
                    let departure = stopTime.departureSeconds - accessSeconds
                    if departure < earliestSeconds { continue }
                    if departure > latestSeconds { break }
                    events.insert(departure)
                }
            }
        }
        return events.sorted(by: >)
    }

    /// Finds a few one-seat alternatives without a graph scan. These remain
    /// internal live-repair reserves; the schedule-only response still exposes
    /// only the canonical profile point for each departure opportunity.
    private nonisolated func directPatternReserves(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext,
        filters: RoutePlannerFilters,
        requestedDepartureSeconds: Int,
        departureWindowEndSeconds: Int,
        arriveByDeadlineSeconds: Int?,
        limit: Int
    ) -> [ScheduledJourney] {
        guard limit > 0 else { return [] }
        let index = context.transitIndex
        let origins = nearestStops(
            to: origin,
            in: context,
            radiusMeters: accessRadiusMeters,
            limit: 8
        )
        let destinations = destinationStopMatches(
            for: destination,
            in: context,
            radiusMeters: destinationRadiusMeters
        )
        var journeys: [ScheduledJourney] = []

        for originCandidate in origins {
            if Task.isCancelled { return [] }
            guard let boardStopIndex = index.stopIndexByID[originCandidate.stop.id] else {
                continue
            }
            let accessSeconds = walkingSeconds(for: originCandidate.distanceMeters)
            for reference in index.patternReferencesByStopIndex[boardStopIndex] {
                let pattern = index.patterns[reference.patternIndex]
                guard let route = context.routesById[pattern.routeID],
                      filters.modePreference.transportMode.map({ $0 == route.transportMode }) ?? true else {
                    continue
                }

                for destinationCandidate in destinations {
                    guard let alightStopIndex = index.stopIndexByID[destinationCandidate.stop.id],
                          let alightPosition = pattern.stopIndices[
                              (reference.stopPosition + 1)...
                          ].firstIndex(of: alightStopIndex) else {
                        continue
                    }
                    let totalWalking = originCandidate.distanceMeters
                        + destinationCandidate.distanceMeters
                    if filters.preferAccessible, totalWalking > 700 { continue }

                    var lower = 0
                    var upper = pattern.tripIndices.count
                    let readySeconds = requestedDepartureSeconds + accessSeconds
                    while lower < upper {
                        let middle = (lower + upper) / 2
                        let trip = context.activeTrips[pattern.tripIndices[middle]]
                        if trip.stopTimes[reference.stopPosition].departureSeconds < readySeconds {
                            lower = middle + 1
                        } else {
                            upper = middle
                        }
                    }

                    var acceptedForPattern = 0
                    for offset in lower ..< pattern.tripIndices.count {
                        let trip = context.activeTrips[pattern.tripIndices[offset]]
                        let boardTime = trip.stopTimes[reference.stopPosition]
                        let alightTime = trip.stopTimes[alightPosition]
                        let doorDepartureSeconds = boardTime.departureSeconds - accessSeconds
                        guard doorDepartureSeconds <= departureWindowEndSeconds else { break }
                        guard boardTime.pickupType != "1", alightTime.dropOffType != "1" else {
                            continue
                        }
                        let destinationArrivalSeconds = alightTime.arrivalSeconds
                            + walkingSeconds(for: destinationCandidate.distanceMeters)
                        if let deadline = arriveByDeadlineSeconds,
                           destinationArrivalSeconds > deadline {
                            continue
                        }
                        guard let boardStop = context.stopsById[boardTime.stopId],
                              let alightStop = context.stopsById[alightTime.stopId] else {
                            continue
                        }

                        var legs: [RoutePlan.Leg] = []
                        if originCandidate.distanceMeters > minimumWalkLegMeters {
                            legs.append(walkingLeg(
                                id: "reserve-access-\(originCandidate.stop.id)",
                                from: origin,
                                to: originCandidate.stop.location,
                                departureSeconds: doorDepartureSeconds,
                                arrivalSeconds: boardTime.departureSeconds,
                                serviceStart: context.serviceStart,
                                distanceMeters: originCandidate.distanceMeters,
                                instruction: "Walk to \(originCandidate.stop.name)"
                            ))
                        }
                        legs.append(scheduledTransitLeg(
                            sequence: legs.count,
                            trip: trip,
                            route: route,
                            boardTime: boardTime,
                            alightTime: alightTime,
                            boardStop: boardStop,
                            alightStop: alightStop,
                            context: context
                        ))
                        if destinationCandidate.distanceMeters > minimumWalkLegMeters {
                            legs.append(walkingLeg(
                                id: "reserve-egress-\(destinationCandidate.stop.id)",
                                from: destinationCandidate.stop.location,
                                to: destination,
                                departureSeconds: alightTime.arrivalSeconds,
                                arrivalSeconds: destinationArrivalSeconds,
                                serviceStart: context.serviceStart,
                                distanceMeters: destinationCandidate.distanceMeters,
                                instruction: "Walk to \(destination.name ?? destinationCandidate.stop.name)"
                            ))
                        }
                        journeys.append(ScheduledJourney(
                            legs: normalizedWalkingLegs(justInTimeLeadingWalk(legs))
                        ))
                        acceptedForPattern += 1
                        if acceptedForPattern == limit { break }
                    }
                }
            }
        }

        var seenSignatures: Set<String> = []
        return journeys
            .filter { seenSignatures.insert($0.signature).inserted }
            .sorted {
                if $0.departureTime != $1.departureTime {
                    return arriveByDeadlineSeconds == nil
                        ? $0.departureTime < $1.departureTime
                        : $0.departureTime > $1.departureTime
                }
                return scheduledRanksBefore($0, $1, filters: filters)
            }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated func boundedWorkingProfile(
        _ journeys: [ScheduledJourney],
        descending: Bool,
        limit: Int,
        filters: RoutePlannerFilters
    ) -> [ScheduledJourney] {
        var seenSignatures: Set<String> = []
        return journeys
            .filter { seenSignatures.insert($0.signature).inserted }
            .sorted {
                if $0.departureTime != $1.departureTime {
                    return descending
                        ? $0.departureTime > $1.departureTime
                        : $0.departureTime < $1.departureTime
                }
                return scheduledRanksBefore($0, $1, filters: filters)
            }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated func uniqueJourneysByDoorDeparture(
        _ journeys: [ScheduledJourney],
        descending: Bool
    ) -> [ScheduledJourney] {
        var bestByDeparture: [Int: ScheduledJourney] = [:]
        for journey in journeys {
            let departure = Int(journey.departureTime.timeIntervalSince1970.rounded())
            if let existing = bestByDeparture[departure] {
                if scheduledRanksBefore(journey, existing, filters: RoutePlannerFilters()) {
                    bestByDeparture[departure] = journey
                }
            } else {
                bestByDeparture[departure] = journey
            }
        }
        return bestByDeparture.keys.sorted(by: descending ? (>) : (<)).compactMap {
            bestByDeparture[$0]
        }
    }
}
