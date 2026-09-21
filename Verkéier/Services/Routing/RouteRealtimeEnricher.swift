import Foundation

/// Adds live departure-board facts to routes that were already calculated
/// from the static timetable. It never adds, removes, reorders, or replans an
/// option, so a delay cannot influence the routing algorithm.
nonisolated struct RouteRealtimeEnricher: Sendable {
    let liveTransitService: any LiveTransitService

    func enrich(_ options: [RouteOption]) async -> [RouteOption] {
        var latest = options
        for await update in updates(for: options) {
            latest = update
        }
        return latest
    }

    /// Publishes a new snapshot whenever one boarding stop's live board
    /// arrives. A slow or unavailable stop must not hold back live data for all
    /// of the other routes already visible in the UI.
    func updates(for options: [RouteOption]) -> AsyncStream<[RouteOption]> {
        let stops = boardingStops(in: options)
        guard !stops.isEmpty else {
            return AsyncStream { continuation in continuation.finish() }
        }

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (String, [Departure]).self) { group in
                    for stop in stops.values {
                        group.addTask {
                            var filter = TransitBoardFilter()
                            filter.durationMinutes = 360
                            filter.maximumJourneys = 100
                            filter.realtimeMode = .full
                            let departures = (try? await liveTransitService.departureBoard(
                                for: stop,
                                filter: filter
                            )) ?? []
                            return (stop.id, departures)
                        }
                    }

                    var boards: [String: [Departure]] = [:]
                    var latest = options
                    for await (stopID, departures) in group {
                        boards[stopID] = departures
                        let enriched = options.map { option in
                            option.applyingLiveDepartures(boards)
                        }
                        if enriched != latest {
                            latest = enriched
                            continuation.yield(enriched)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func boardingStops(in options: [RouteOption]) -> [String: Stop] {
        var stops: [String: Stop] = [:]
        for leg in options.flatMap(\.transitLegs) {
            guard let stopID = leg.originStopId, stops.index(forKey: stopID) == nil else { continue }
            stops[stopID] = Stop(
                id: stopID,
                name: leg.origin.name ?? "Stop",
                location: leg.origin,
                modes: [leg.mode],
                dataSource: .gtfs,
                gtfsStopID: stopID
            )
        }
        return stops
    }
}

private extension RouteOption {
    nonisolated func applyingLiveDepartures(_ boards: [String: [Departure]]) -> RouteOption {
        let updatedLegs = plan.legs.map { leg -> RoutePlan.Leg in
            guard leg.transportKind == .transit,
                  let stopID = leg.originStopId,
                  let departures = boards[stopID],
                  let departure = departures.bestMatch(for: leg)
            else { return leg }
            return leg.applying(departure)
        }
        guard updatedLegs != plan.legs else { return self }

        return RouteOption(
            id: id,
            plan: RoutePlan(
                id: plan.id,
                origin: plan.origin,
                destination: plan.destination,
                expectedTravelTime: plan.expectedTravelTime,
                distanceMeters: plan.distanceMeters,
                legs: updatedLegs,
                dataSource: plan.dataSource
            ),
            mapOverlay: mapOverlay
        )
    }
}

private extension Array where Element == Departure {
    nonisolated func bestMatch(for leg: RoutePlan.Leg) -> Departure? {
        guard let scheduled = leg.scheduledDepartureTime ?? leg.departureTime else { return nil }
        return compactMap { departure -> (Departure, Int, TimeInterval)? in
            guard let liveScheduled = departure.scheduledDeparture,
                  abs(liveScheduled.timeIntervalSince(scheduled)) <= 90
            else { return nil }

            let routeMatches = departure.routeId?.caseInsensitiveCompare(leg.routeId ?? "") == .orderedSame
                || departure.lineName.normalizedForSearch == (leg.routeName ?? "").normalizedForSearch
            guard routeMatches else { return nil }

            let destinationMatches = leg.headsign.map {
                departure.destination.identifiesSameStation(as: $0)
            } ?? false
            let journeyMatches = departure.journeyReference != nil
                && departure.journeyReference == leg.tripId
            let confidence = journeyMatches ? 3 : (destinationMatches ? 2 : 1)
            return (departure, confidence, abs(liveScheduled.timeIntervalSince(scheduled)))
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 > rhs.1
        }
        .first?.0
    }
}

private extension RoutePlan.Leg {
    nonisolated func applying(_ departure: Departure) -> RoutePlan.Leg {
        let scheduledDeparture = scheduledDepartureTime ?? departureTime
        let delay = departure.delayMinutes
        let realtimeDeparture = departure.realtimeDeparture
        let status: RouteLegLiveStatus = if departure.isCancelled {
            .cancelled
        } else if departure.isStatusUnknown {
            .unknown
        } else if realtimeDeparture != nil || delay != nil {
            (delay ?? 0) > 0 ? .delayed : .live
        } else {
            .scheduled
        }

        var replacement = RoutePlan.Leg(
            id: id,
            mode: mode,
            instruction: instruction,
            transportKind: transportKind,
            routeName: routeName,
            headsign: headsign,
            routeId: routeId,
            tripId: tripId,
            originStopId: originStopId,
            destinationStopId: destinationStopId,
            stopCount: stopCount,
            origin: origin,
            destination: destination,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            scheduledDepartureTime: scheduledDeparture,
            scheduledArrivalTime: scheduledArrivalTime,
            realtimeDepartureTime: realtimeDeparture,
            realtimeArrivalTime: nil,
            distanceMeters: distanceMeters,
            mapCoordinates: mapCoordinates,
            roadRoutingHint: roadRoutingHint,
            platform: departure.platform ?? platform,
            delayMinutes: delay,
            liveStatus: status,
            transferWarning: transferWarning,
            bikeShareDetails: bikeShareDetails
        )
        replacement.departureTimingSource = realtimeDeparture == nil ? departureTimingSource : .observed
        replacement.arrivalTimingSource = arrivalTimingSource
        replacement.requiredTransferSeconds = requiredTransferSeconds
        return replacement
    }
}
