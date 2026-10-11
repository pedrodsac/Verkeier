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
    /// An on-foot stretch (walk or transfer) — drawn solid green.
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

/// Which side of a vel'OH! rental a place represents.
enum BikeSharePlaceRole: Equatable {
    case pickup
    case returnStation
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
        /// Continue on the same vehicle, including a change of route number.
        case stayAboard
        /// Get off a ride onto a final walk.
        case alight
        /// Journey end.
        case destination
    }

    var stayAboardAccessibilityLabel: String {
        "Stay aboard at \(name). \(stayAboardDetail)"
    }

    var stayAboardDetail: String {
        if let continuationLineName {
            return String(localized: "This vehicle continues as line \(continuationLineName). No need to get off.")
        }
        return String(localized: "Continue on the same vehicle. No need to get off.")
    }
    let id: String
    let name: String
    let role: Role
    /// Effective arrival from the incoming leg (`nil` at the origin).
    let arrivalTime: Date?
    /// Effective departure of the outgoing leg (`nil` at the destination).
    let departureTime: Date?
    /// Timetabled arrival before realtime changes. The row displays this only
    /// when it differs from ``arrivalTime``.
    let scheduledArrivalTime: Date?
    /// Timetabled departure before realtime changes. The row displays this only
    /// when it differs from ``departureTime``.
    let scheduledDepartureTime: Date?
    /// Minutes spent here between arriving and departing, when `>= 1` — the
    /// "N min to change" figure at a transfer.
    let waitMinutes: Int?
    /// Realtime delay in minutes of the outgoing transit leg, when live.
    let delayMinutes: Int?
    /// Live status of the outgoing transit leg.
    let liveStatus: RouteLegLiveStatus
    /// `true` when VoiceOver should announce a delay or cancellation.
    let announcesDelay: Bool
    /// Boarding platform of the outgoing transit leg, when published.
    let platform: String?
    /// Tight-transfer warning for the leg boarded here, when at risk. The
    /// warning belongs to the leg being *boarded* (see ``RoutePlan/Leg/transferWarning``),
    /// so it lands on the place where you board it, not the ride segment.
    let transferWarning: String?
    /// The vel'OH! station at this place, when it is a pickup or return point.
    let bikeShareStation: BikeShareStation?
    /// Whether the station is used to pick up a bike or return one.
    let bikeShareStationRole: BikeSharePlaceRole?
    /// Rail style entering from above (`nil` for the first place).
    let railAbove: RailStyle?
    /// Rail style leaving below (`nil` for the final place).
    let railBelow: RailStyle?
    /// Published line name when the same vehicle changes lines here.
    var continuationLineName: String? = nil
}

/// One leg of the journey: walk, transfer, or transit ride.
struct SegmentNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case walk
        case transfer
        case transit
        case bikeShare
        case funicular
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
    let stopCount: Int?
    let distanceMeters: Double?
    let rail: RailStyle
    let bikeShareDetails: BikeShareLegDetails?
    var tripSelection: TripDetailSelection? = nil
    var continuationCaptions: [String] = []
    var sourceSegmentIDs: [String] = []
    var hasCancelledContinuation = false
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
            items.append(.segment(segmentNode(id: "segment-\(index)", leg: leg, prev: prev, next: next, followingLegs: Array(legs.dropFirst(index + 1)))))
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
        let outgoingTransit = outgoing?.transportKind == .transit && outgoing?.mode != .funicular ? outgoing : nil
        let placeRole = role(incoming: incoming, outgoing: outgoing)

        let arrival = incoming.flatMap { $0.mode == .funicular ? nil : arrivalTime(of: $0) }
        // A continuous funicular connection has no fixed boarding/alighting
        // time. Keep the adjoining scheduled vehicle time when there is one.
        let departure = outgoing.flatMap {
            $0.mode == .funicular || (incoming?.mode == .funicular && $0.transportKind != .transit)
                ? nil : departureTime(of: $0)
        }

        let wait: Int? = {
            guard let arrival, let departure else { return nil }
            return DurationDisplay.minutes(departure.timeIntervalSince(arrival), rounding: .up)
        }()

        // Announce only when there's something to say: a non-zero delay or a
        // cancellation. An on-time live leg needs no extra wording.
        let status = outgoingTransit?.liveStatus ?? .scheduled
        let delay = outgoingTransit?.delayMinutes ?? 0
        let announcesDelay = status == .cancelled || (status != .scheduled && delay != 0)
        let pickupStation = outgoing?.transportKind == .bikeShare
            ? outgoing?.bikeShareDetails?.pickupStation
            : nil
        let returnStation = incoming?.transportKind == .bikeShare
            ? incoming?.bikeShareDetails?.returnStation
            : nil
        let bikeShareStation = pickupStation ?? returnStation
        let bikeShareStationRole: BikeSharePlaceRole? = if pickupStation != nil {
            .pickup
        } else if returnStation != nil {
            .returnStation
        } else {
            nil
        }

        return PlaceNode(
            id: id,
            name: (point.name ?? "Stop").stationDisplayName(hidingLocality: incoming?.mode == .tram || outgoing?.mode == .tram),
            role: placeRole,
            arrivalTime: arrival,
            departureTime: departure,
            scheduledArrivalTime: incoming?.transportKind == .transit && incoming?.mode != .funicular
                ? incoming?.scheduledArrivalTime
                : nil,
            scheduledDepartureTime: outgoingTransit?.scheduledDepartureTime,
            waitMinutes: placeRole == .stayAboard ? nil : wait,
            delayMinutes: outgoingTransit?.delayMinutes,
            liveStatus: status,
            announcesDelay: announcesDelay,
            platform: placeRole == .stayAboard ? nil : outgoingTransit?.platform,
            transferWarning: placeRole == .stayAboard ? nil : outgoingTransit?.transferWarning,
            bikeShareStation: bikeShareStation,
            bikeShareStationRole: bikeShareStationRole,
            railAbove: incoming.map(railStyle(for:)),
            railBelow: outgoing.map(railStyle(for:)),
            continuationLineName: placeRole == .stayAboard && incoming?.routeName != outgoing?.routeName
                ? outgoing?.routeName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                : nil
        )
    }

    /// Classifies a place from the modes of the legs meeting there. A direct
    /// ride→ride change is a `.transfer`; a walk between two rides splits into an
    /// `.alight` (get off) and a `.board` (get on) with the walk segment between.
    private static func role(incoming: RoutePlan.Leg?, outgoing: RoutePlan.Leg?) -> PlaceNode.Role {
        guard let incoming else { return .origin }
        guard let outgoing else { return .destination }
        if outgoing.continuesInSeatFromTripID == incoming.tripId, outgoing.continuesInSeatFromTripID != nil { return .stayAboard }
        switch (incoming.transportKind == .transit && incoming.mode != .funicular,
                outgoing.transportKind == .transit && outgoing.mode != .funicular) {
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
        next: RoutePlan.Leg?,
        followingLegs: [RoutePlan.Leg]
    ) -> SegmentNode {
        let kind: SegmentNode.Kind = if leg.mode == .funicular {
            .funicular
        } else if leg.transportKind == .transit {
            .transit
        } else if leg.transportKind == .bikeShare {
            .bikeShare
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
            badgeText: kind == .transit ? leg.routeName : (kind == .bikeShare ? "vel’OH!" : nil),
            headsign: kind == .transit ? leg.headsign?.stationDisplayName(hidingLocality: leg.mode == .tram) : nil,
            durationMinutes: durationMinutes(of: leg),
            stopCount: kind == .transit ? leg.stopCount : nil,
            distanceMeters: kind == .transit ? nil : leg.distanceMeters,
            rail: railStyle(for: leg),
            bikeShareDetails: leg.bikeShareDetails,
            tripSelection: kind == .transit ? TripDetailSelection(leg: leg, followingLegs: followingLegs) : nil
        )
    }

    // MARK: - Helpers

    private nonisolated static func railStyle(for leg: RoutePlan.Leg) -> RailStyle {
        leg.transportKind == .transit || leg.transportKind == .bikeShare
            ? .transit(leg.mode)
            : .walk
    }

    private static func departureTime(of leg: RoutePlan.Leg) -> Date? {
        leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
    }

    private static func arrivalTime(of leg: RoutePlan.Leg) -> Date? {
        leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
    }

    private static func durationMinutes(of leg: RoutePlan.Leg) -> Int? {
        guard let dep = departureTime(of: leg), let arr = arrivalTime(of: leg) else { return nil }
        let rounding: FloatingPointRoundingRule = leg.transportKind == .walking || leg.mode == .funicular
            ? .up : .toNearestOrAwayFromZero
        return DurationDisplay.minutes(arr.timeIntervalSince(dep), rounding: rounding)
    }
}
