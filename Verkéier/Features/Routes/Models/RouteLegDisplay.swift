import Foundation

/// Collapses verified stay-aboard boundaries into the first ride's row while
/// preserving original segment identities for alerts and journey navigation.
enum RouteLegDisplay {
    /// One line badge per vehicle ride; funicular connections become one walk chip.
    static func ribbonLegs(from legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        let displayLegs = combiningFunicularConnections(in: legs)
        return displayLegs.enumerated().compactMap { index, leg in
            guard leg.mode != .funicular else { return nil }
            guard [.transit, .walking, .bikeShare].contains(leg.transportKind) else { return nil }
            if index > 0, leg.transportKind == .transit {
                let incoming = displayLegs[index - 1]
                if incoming.transportKind == .transit, let tripID = incoming.tripId,
                    leg.continuesInSeatFromTripID == tripID
                {
                    return nil
                }
            }
            return leg
        }
    }

    /// Only the card ribbon uses these synthetic legs. Routing and the detailed
    /// timeline retain the separate walks and purple funicular ride.
    private static func combiningFunicularConnections(in legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result: [RoutePlan.Leg] = []
        var index = 0
        while index < legs.count {
            let first = legs[index]
            guard first.transportKind == .walking || first.mode == .funicular else {
                result.append(first)
                index += 1
                continue
            }
            var end = index + 1
            while end < legs.count,
                legs[end].transportKind == .walking || legs[end].mode == .funicular
            {
                end += 1
            }
            let connection = legs[index..<end]
            if connection.contains(where: { $0.mode == .funicular }) {
                let durations = connection.compactMap { leg -> TimeInterval? in
                    let departure = leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
                    let arrival = leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
                    guard let departure, let arrival else { return nil }
                    return max(0, arrival.timeIntervalSince(departure))
                }
                let departure = first.realtimeDepartureTime ?? first.scheduledDepartureTime ?? first.departureTime
                let duration = durations.count == connection.count ? durations.reduce(0, +) : nil
                result.append(
                    RoutePlan.Leg(
                        id: first.id,
                        mode: .walking,
                        transportKind: .walking,
                        origin: first.origin,
                        destination: legs[end - 1].destination,
                        departureTime: departure,
                        arrivalTime: departure.flatMap { start in duration.map { start.addingTimeInterval($0) } }
                    )
                )
            } else {
                result.append(contentsOf: connection)
            }
            index = end
        }
        return result
    }

    static func timelineItems(from legs: [RoutePlan.Leg]) -> [RouteTimelineItem] {
        let original = RouteTimelineBuilder.items(from: legs)
        var result: [RouteTimelineItem] = []
        var index = 0
        while index < original.count {
            guard case let .segment(first) = original[index] else {
                result.append(original[index])
                index += 1
                continue
            }
            let firstLegIndex = index / 2
            var segments = [first]
            var captions: [String] = []
            var cancelled = false
            while first.kind == .transit, index + 2 < original.count,
                case let .place(boundary) = original[index + 1], boundary.role == .stayAboard,
                case let .segment(onward) = original[index + 2], onward.kind == .transit
            {
                segments.append(onward)
                let line = onward.badgeText ?? onward.mode.displayName
                if let headsign = onward.headsign, !headsign.isEmpty {
                    captions.append(String(localized: "Continues as \(line): \(headsign)"))
                } else {
                    captions.append(String(localized: "Continues as \(line)"))
                }
                cancelled = cancelled || boundary.liveStatus == .cancelled
                index += 2
            }
            if segments.count == 1 {
                result.append(.segment(first))
            } else {
                let lastLeg = legs[index / 2]
                let firstLeg = legs[firstLegIndex]
                let departure =
                    firstLeg.realtimeDepartureTime ?? firstLeg.scheduledDepartureTime ?? firstLeg.departureTime
                let arrival = lastLeg.realtimeArrivalTime ?? lastLeg.scheduledArrivalTime ?? lastLeg.arrivalTime
                let minutes = departure.flatMap { departure in
                    arrival.map { Int(($0.timeIntervalSince(departure) / 60).rounded()) }
                }
                let counts = segments.compactMap(\.stopCount)
                result.append(
                    .segment(
                        SegmentNode(
                            id: first.id,
                            kind: first.kind,
                            mode: first.mode,
                            badgeText: first.badgeText,
                            headsign: first.headsign,
                            durationMinutes: minutes.flatMap { $0 > 0 ? $0 : nil },
                            stopCount: counts.count == segments.count ? counts.reduce(0, +) : nil,
                            distanceMeters: first.distanceMeters,
                            rail: first.rail,
                            bikeShareDetails: first.bikeShareDetails,
                            tripSelection: first.tripSelection,
                            continuationCaptions: captions,
                            sourceSegmentIDs: segments.map(\.id),
                            hasCancelledContinuation: cancelled
                        )
                    )
                )
            }
            index += 1
        }
        return result
    }
}
