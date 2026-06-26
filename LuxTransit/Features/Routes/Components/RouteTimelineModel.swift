import Foundation

// Pure, view-independent model for the place-centric route timeline.
//
// A journey of `N` legs is flattened into an alternating list of `N + 1`
// *places* (the stations/addresses where legs meet) and `N` *segments* (the
// walk/transfer/ride that connects them). Each item carries the rail styles it
// needs so the SwiftUI views stay dumb. See ``RouteTimelineBuilder``.

/// Visual treatment for a stretch of the connecting rail.
enum RailStyle: Equatable {
    /// A transit ride — drawn solid in the mode's tint.
    case transit(TransportMode)
    /// An on-foot stretch (walk or transfer) — drawn dotted green.
    case walk
}

/// One row in the timeline: a place (dot) or a segment (line + description).
enum RouteTimelineItem: Identifiable, Equatable {
    case place(PlaceNode)
    case segment(SegmentNode)

    var id: String {
        switch self {
        case let .place(node): node.id
        case let .segment(node): node.id
        }
    }
}

/// A station / address where the journey starts, ends, or changes legs.
struct PlaceNode: Identifiable, Equatable {
    let id: String
    let name: String
    /// Boarding time for a place with an outgoing leg; arrival for the final place.
    let time: Date?
    /// Realtime delay in minutes of the outgoing transit leg, when live.
    let delayMinutes: Int?
    /// Live status of the outgoing transit leg, used to colour the delay badge.
    let liveStatus: RouteLegLiveStatus
    /// `true` when the outgoing leg has realtime data worth badging.
    let showsDelayBadge: Bool
    /// Boarding platform of the outgoing transit leg, when published.
    let platform: String?
    /// Rail style entering from above (`nil` for the first place).
    let railAbove: RailStyle?
    /// Rail style leaving below (`nil` for the final place).
    let railBelow: RailStyle?
}

/// One leg of the journey: walk, transfer, or transit ride.
struct SegmentNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case walk
        case transfer
        case transit
    }

    let id: String
    let kind: Kind
    let mode: TransportMode
    /// Line label for transit legs (e.g. "T1", "29").
    let badgeText: String?
    /// Line terminus / direction name for transit legs.
    let headsign: String?
    let durationMinutes: Int?
    let distanceMeters: Double?
    let transferWarning: String?
    let rail: RailStyle
}

// MARK: - Builder

enum RouteTimelineBuilder {
    static func items(from legs: [RoutePlan.Leg]) -> [RouteTimelineItem] {
        guard !legs.isEmpty else { return [] }

        var items: [RouteTimelineItem] = []
        for (index, leg) in legs.enumerated() {
            let prev = index > 0 ? legs[index - 1] : nil
            let next = index + 1 < legs.count ? legs[index + 1] : nil

            items.append(.place(placeNode(
                id: "place-\(index)",
                point: leg.origin,
                incoming: prev,
                outgoing: leg
            )))
            items.append(.segment(segmentNode(id: "segment-\(index)", leg: leg, prev: prev, next: next)))
        }

        // Final place: the last leg's destination, arrival only.
        let last = legs[legs.count - 1]
        items.append(.place(placeNode(
            id: "place-\(legs.count)",
            point: last.destination,
            incoming: last,
            outgoing: nil
        )))

        return items
    }

    // MARK: - Place

    private static func placeNode(
        id: String,
        point: LocationPoint,
        incoming: RoutePlan.Leg?,
        outgoing: RoutePlan.Leg?
    ) -> PlaceNode {
        let outgoingTransit = outgoing?.transportKind == .transit ? outgoing : nil
        // Boarding time when leaving here, otherwise the arrival from below.
        let time = outgoing.map { departureTime(of: $0) } ?? incoming.map { arrivalTime(of: $0) } ?? nil

        // Badge only when there's something to say: a non-zero delay or a cancellation.
        // An on-time live leg shows no "+0" — on time needs no callout.
        let status = outgoingTransit?.liveStatus ?? .scheduled
        let delay = outgoingTransit?.delayMinutes ?? 0
        let showsDelayBadge = status == .cancelled || (status != .scheduled && delay != 0)

        return PlaceNode(
            id: id,
            name: point.name ?? "Stop",
            time: time,
            delayMinutes: outgoingTransit?.delayMinutes,
            liveStatus: status,
            showsDelayBadge: showsDelayBadge,
            platform: outgoingTransit?.platform,
            railAbove: incoming.map(railStyle(for:)),
            railBelow: outgoing.map(railStyle(for:))
        )
    }

    // MARK: - Segment

    private static func segmentNode(
        id: String,
        leg: RoutePlan.Leg,
        prev: RoutePlan.Leg?,
        next: RoutePlan.Leg?
    ) -> SegmentNode {
        let kind: SegmentNode.Kind = if leg.transportKind == .transit {
            .transit
        } else if leg.transportKind == .walking,
                  prev?.transportKind == .transit, next?.transportKind == .transit {
            // A walk wedged between two rides is a transfer, not an access walk.
            .transfer
        } else {
            .walk
        }

        return SegmentNode(
            id: id,
            kind: kind,
            mode: leg.mode,
            badgeText: kind == .transit ? leg.routeName : nil,
            headsign: kind == .transit ? (leg.headsign ?? leg.destination.name) : nil,
            durationMinutes: durationMinutes(of: leg),
            distanceMeters: kind == .transit ? nil : leg.distanceMeters,
            transferWarning: leg.transferWarning,
            rail: railStyle(for: leg)
        )
    }

    // MARK: - Helpers

    private static func railStyle(for leg: RoutePlan.Leg) -> RailStyle {
        leg.transportKind == .transit ? .transit(leg.mode) : .walk
    }

    private static func departureTime(of leg: RoutePlan.Leg) -> Date? {
        leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
    }

    private static func arrivalTime(of leg: RoutePlan.Leg) -> Date? {
        leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
    }

    private static func durationMinutes(of leg: RoutePlan.Leg) -> Int? {
        guard let dep = departureTime(of: leg), let arr = arrivalTime(of: leg) else { return nil }
        let minutes = Int((arr.timeIntervalSince(dep) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }
}
