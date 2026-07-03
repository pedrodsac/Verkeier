import Foundation

// Pure, view-independent model for the place-centric route timeline.
//
// A journey of `N` legs is flattened into an alternating list of `N + 1`
// *places* (the stations/addresses where legs meet) and `N` *segments* (the
// walk/transfer/ride that connects them). Each item carries the rail styles and
// derived facts it needs so the SwiftUI views stay dumb. See ``RouteTimelineBuilder``.
//
// Id contract: places are `"place-<index>"` and segments `"segment-<index>"`
// (index = leg index). `RouteLegList` keys per-leg alerts off the segment ids,
// so these strings are a stable API — changing them silently breaks alert
// wiring. `RouteTimelineBuilderTests` pins them.

/// Visual treatment for a stretch of the connecting rail.
enum RailStyle: Equatable {
    /// A transit ride — drawn solid in the mode's tint.
    case transit(TransportMode)
    /// An on-foot stretch (walk or transfer) — drawn dotted green.
    case walk
}

/// One row in the timeline: a place (marker) or a segment (line + description).
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
    /// The place's part in the journey, driving its marker and typography.
    enum Role: Equatable {
        /// Journey start.
        case origin
        /// Board a transit leg after walking (or straight from the origin).
        case board
        /// Change directly between two rides at the same stop (arrive + depart).
        case transfer
        /// Get off a ride onto a final walk.
        case alight
        /// Journey end.
        case destination
    }

    let id: String
    let name: String
    let role: Role
    /// Effective arrival from the incoming leg (`nil` at the origin).
    let arrivalTime: Date?
    /// Effective departure of the outgoing leg (`nil` at the destination).
    let departureTime: Date?
    /// Minutes spent here between arriving and departing, when `>= 1` — the
    /// "N min to change" figure at a transfer.
    let waitMinutes: Int?
    /// Realtime delay in minutes of the outgoing transit leg, when live.
    let delayMinutes: Int?
    /// Live status of the outgoing transit leg, used to colour the delay badge.
    let liveStatus: RouteLegLiveStatus
    /// `true` when the outgoing leg has realtime data worth badging.
    let showsDelayBadge: Bool
    /// Boarding platform of the outgoing transit leg, when published.
    let platform: String?
    /// Tight-transfer warning for the leg boarded here, when at risk. The
    /// warning belongs to the leg being *boarded* (see ``RoutePlan/Leg/transferWarning``),
    /// so it lands on the place where you board it, not the ride segment.
    let transferWarning: String?
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
    /// Line terminus / direction for transit legs — the "toward …" name. `nil`
    /// when the feed gives no headsign (never the alighting stop; that would
    /// misread as "where you get off").
    let headsign: String?
    let durationMinutes: Int?
    let distanceMeters: Double?
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

        let arrival = incoming.flatMap { arrivalTime(of: $0) }
        let departure = outgoing.flatMap { departureTime(of: $0) }

        let wait: Int? = {
            guard let arrival, let departure else { return nil }
            let minutes = Int((departure.timeIntervalSince(arrival) / 60).rounded())
            return minutes >= 1 ? minutes : nil
        }()

        // Badge only when there's something to say: a non-zero delay or a
        // cancellation. An on-time live leg shows no "+0".
        let status = outgoingTransit?.liveStatus ?? .scheduled
        let delay = outgoingTransit?.delayMinutes ?? 0
        let showsDelayBadge = status == .cancelled || (status != .scheduled && delay != 0)

        return PlaceNode(
            id: id,
            name: point.name ?? "Stop",
            role: role(incoming: incoming, outgoing: outgoing),
            arrivalTime: arrival,
            departureTime: departure,
            waitMinutes: wait,
            delayMinutes: outgoingTransit?.delayMinutes,
            liveStatus: status,
            showsDelayBadge: showsDelayBadge,
            platform: outgoingTransit?.platform,
            transferWarning: outgoingTransit?.transferWarning,
            railAbove: incoming.map(railStyle(for:)),
            railBelow: outgoing.map(railStyle(for:))
        )
    }

    /// Classifies a place from the modes of the legs meeting there. A direct
    /// ride→ride change is a `.transfer`; a walk between two rides splits into an
    /// `.alight` (get off) and a `.board` (get on) with the walk segment between.
    private static func role(incoming: RoutePlan.Leg?, outgoing: RoutePlan.Leg?) -> PlaceNode.Role {
        guard let incoming else { return .origin }
        guard let outgoing else { return .destination }
        switch (incoming.transportKind == .transit, outgoing.transportKind == .transit) {
        case (true, true): return .transfer
        case (true, false): return .alight
        default: return .board
        }
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
            headsign: kind == .transit ? leg.headsign : nil,
            durationMinutes: durationMinutes(of: leg),
            distanceMeters: kind == .transit ? nil : leg.distanceMeters,
            rail: railStyle(for: leg)
        )
    }

    // MARK: - Helpers

    private nonisolated static func railStyle(for leg: RoutePlan.Leg) -> RailStyle {
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
