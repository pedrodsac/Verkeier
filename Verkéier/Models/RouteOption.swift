import Foundation

/// A presentable route alternative: a ``RoutePlan`` plus map overlay and a set
/// of derived, UI-friendly properties.
///
/// The route planner returns several options; the computed properties here
/// (transfer count, walking distance, live-data usage, and ``status(at:)``)
/// drive both sorting and the badges shown for each alternative.
nonisolated struct RouteOption: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier for the option.
    let id: String
    /// The underlying journey plan.
    let plan: RoutePlan
    /// Pre-built map geometry for drawing the option, if available.
    let mapOverlay: RouteMapOverlay?

    /// The plan's transit legs (excludes walking/driving).
    var transitLegs: [RoutePlan.Leg] {
        plan.legs.filter { $0.transportKind == .transit }
    }

    /// Departure time of the first transit leg, preferring realtime over
    /// scheduled times. Bike-only plans fall back to their first leg so the
    /// value remains useful to callers that need a transit departure time.
    var firstTransitDepartureTime: Date? {
        let transitDeparture = transitLegs.compactMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }.min()
        return transitDeparture ?? plan.legs.first.flatMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }
    }

    /// Door-to-door departure of the whole journey — the effective departure of
    /// the first leg, *including* any initial access walk. Mirrors ``arrivalTime``
    /// so the detail timeline's first row and the summary header open on the same
    /// minute. (``firstTransitDepartureTime`` remains the "when does my bus leave"
    /// figure used for status and transit-specific presentation.)
    var departureTime: Date? {
        plan.legs.first.flatMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }
    }

    /// Arrival time at the destination, preferring realtime over scheduled.
    var arrivalTime: Date? {
        plan.legs.compactMap {
            $0.realtimeArrivalTime ?? $0.scheduledArrivalTime ?? $0.arrivalTime
        }.last
    }

    /// Number of transfers between transit legs (always `>= 0`).
    var transferCount: Int {
        max(0, transitLegs.count - 1)
    }

    /// Distinct line labels used by the option, in order.
    var routeNames: [String] {
        var seen: Set<String> = []
        return transitLegs.compactMap(\.routeName).filter { seen.insert($0).inserted }
    }

    /// `true` when any transit leg carries realtime information.
    var usesLiveData: Bool {
        transitLegs.contains { leg in
            leg.realtimeDepartureTime != nil
                || leg.realtimeArrivalTime != nil
                || leg.delayMinutes != nil
                || leg.liveStatus == .live
                || leg.liveStatus == .delayed
                || leg.liveStatus == .cancelled
        }
    }

    /// Routes may mix live and timetable-only services because ATP does not
    /// provide predictions for every line. Those schedule-only legs remain useful,
    /// but the option must not imply that every connection is live-confirmed.
    var realtimeCoverage: RouteRealtimeCoverage {
        let legs = transitLegs
        guard !legs.isEmpty else { return .scheduleOnly }

        let hasLiveLeg = legs.contains {
            $0.liveStatus == .live || $0.liveStatus == .delayed || $0.liveStatus == .cancelled
        }
        let hasScheduledLeg = legs.contains {
            $0.liveStatus == .scheduled || $0.liveStatus == .unknown
        }
        if hasLiveLeg, hasScheduledLeg { return .partial }
        return hasLiveLeg ? .live : .scheduleOnly
    }

    var usesBikeShare: Bool {
        plan.legs.contains { $0.transportKind == .bikeShare }
    }

    /// True for a vel'OH! journey with only the walking access/egress legs
    /// needed to reach its stations. Transit-bike combinations remain regular
    /// transit options for time-range and missed-departure presentation.
    var isVelohOnly: Bool {
        usesBikeShare && plan.legs.allSatisfy {
            $0.transportKind == .bikeShare || $0.transportKind == .walking
        }
    }

    var hasBikeAvailabilityWarning: Bool {
        plan.legs.contains { $0.bikeShareDetails?.isAvailabilityWarning == true }
    }

    /// Total walking distance across all walking legs, in metres.
    var walkingDistanceMeters: Double {
        plan.legs
            .filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    /// True when any leg endpoint lies outside Luxembourg's bounding box — the
    /// journey likely crosses into France, Germany, or Belgium, where ATP
    /// real-time coverage of CFL/SNCF/DB connections may be incomplete.
    var crossesBorder: Bool {
        func insideLuxembourg(_ point: LocationPoint) -> Bool {
            (49.44 ... 50.19).contains(point.latitude) && (5.73 ... 6.54).contains(point.longitude)
        }
        return plan.legs.contains { !insideLuxembourg($0.origin) || !insideLuxembourg($0.destination) }
    }

    /// Resolves the option's status relative to a reference time.
    ///
    /// Resolution order: cancelled → missed (transit first departure already
    /// gone, with a 30s grace) → Connection miss → at-risk (any tight
    /// transfer) → live / partly-live / schedule-only. Vel'OH!-only plans never
    /// become missed.
    ///
    /// - Parameter now: The reference time, usually the current date.
    func status(at now: Date) -> RouteOptionStatus {
        if transitLegs.contains(where: { $0.liveStatus == .cancelled }) {
            return .cancelled
        }

        if !isVelohOnly,
           let firstTransitDepartureTime,
           firstTransitDepartureTime.addingTimeInterval(30) < now {
            return .missed
        }

        if transitLegs.contains(where: { $0.transferWarning == "Connection miss" }) {
            return .connectionMayBeMissed
        }

        if transitLegs.contains(where: { $0.transferWarning != nil }) {
            return .atRisk
        }

        switch realtimeCoverage {
        case .live:
            return .viable
        case .partial:
            return .partiallyLive
        case .scheduleOnly:
            return .scheduledOnly
        }
    }
}

/// Completeness of realtime evidence across a route's transit legs.
nonisolated enum RouteRealtimeCoverage: String, Codable, Hashable {
    case live
    case partial
    case scheduleOnly

    var displayText: String {
        switch self {
        case .live: "Live"
        case .partial: "Partly live"
        case .scheduleOnly: "Schedule only"
        }
    }
}

/// Overall viability of a ``RouteOption`` at a given time, used for badges and
/// filtering.
nonisolated enum RouteOptionStatus: String, Codable, Hashable {
    /// Backed by live data and currently catchable.
    case viable
    /// Catchable, but one or more legs have timetable-only data.
    case partiallyLive
    /// Timetable-only; no realtime confirmation.
    case scheduledOnly
    /// Reachable but contains a tight transfer.
    case atRisk
    /// A transfer has insufficient time to be made reliably.
    case connectionMayBeMissed
    /// The first departure has already left.
    case missed
    /// A leg has been cancelled.
    case cancelled

    /// Short label suitable for a badge.
    var displayText: String {
        switch self {
        case .viable: "Live"
        case .partiallyLive: "Partly live"
        case .scheduledOnly: "Schedule only"
        case .atRisk: "Tight transfer"
        case .connectionMayBeMissed: "Connection miss"
        case .missed: "Missed"
        case .cancelled: "Cancelled"
        }
    }
}
