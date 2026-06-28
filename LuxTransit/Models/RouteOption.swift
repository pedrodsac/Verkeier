import Foundation

/// A presentable route alternative: a ``RoutePlan`` plus map overlay and a set
/// of derived, UI-friendly properties.
///
/// The route planner returns several options; the computed properties here
/// (transfer count, walking distance, live-data usage, and ``status(at:)``)
/// drive both sorting and the badges shown for each alternative.
nonisolated struct RouteOption: Codable, Hashable, Identifiable {
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
    /// scheduled times.
    var firstTransitDepartureTime: Date? {
        transitLegs.compactMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }.min()
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
    /// Resolution order: cancelled → missed (first departure already gone, with
    /// a 30s grace) → at-risk (any tight transfer) → viable (uses live data) →
    /// scheduled-only.
    ///
    /// - Parameter now: The reference time, usually the current date.
    func status(at now: Date) -> RouteOptionStatus {
        if transitLegs.contains(where: { $0.liveStatus == .cancelled }) {
            return .cancelled
        }

        if let firstTransitDepartureTime,
           firstTransitDepartureTime.addingTimeInterval(30) < now {
            return .missed
        }

        if transitLegs.contains(where: { $0.transferWarning != nil }) {
            return .atRisk
        }

        if usesLiveData {
            return .viable
        }

        return .scheduledOnly
    }
}

/// Overall viability of a ``RouteOption`` at a given time, used for badges and
/// filtering.
nonisolated enum RouteOptionStatus: String, Codable, Hashable {
    /// Backed by live data and currently catchable.
    case viable
    /// Timetable-only; no realtime confirmation.
    case scheduledOnly
    /// Reachable but contains a tight transfer.
    case atRisk
    /// The first departure has already left.
    case missed
    /// A leg has been cancelled.
    case cancelled

    /// Short label suitable for a badge.
    var displayText: String {
        switch self {
        case .viable: "Live"
        case .scheduledOnly: "Scheduled"
        case .atRisk: "Tight transfer"
        case .missed: "Missed"
        case .cancelled: "Cancelled"
        }
    }
}
