import Foundation
import MobiliteitKit

/// A presentable route alternative: a ``RoutePlan`` plus map overlay and a set
/// of derived, UI-friendly properties.
///
/// The route planner returns several options; the computed properties here
/// (transfer count, walking distance, live-data usage, and ``status(at:)``)
/// supply display values and badges from package journey evidence.
nonisolated struct RouteOption: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier for the option.
    let id: String
    /// The underlying journey plan.
    let plan: RoutePlan
    /// Pre-built map geometry for drawing the option, if available.
    let mapOverlay: RouteMapOverlay?
    var feasibility: RouteFeasibility? = nil
    var journeySummary: JourneySummary? = nil
    var statusEvidence: JourneyStatusEvidence? = nil
    var validationContext: RouteValidationContext? = nil
    var refinementToken: JourneyRefinementToken? = nil

    /// The plan's transit legs (excludes walking/driving).
    var transitLegs: [RoutePlan.Leg] {
        plan.legs.filter { $0.transportKind == .transit }
    }

    /// Departure time of the first transit leg, preferring realtime over
    /// scheduled times. Bike-only plans fall back to their first leg so the
    /// value remains useful to callers that need a transit departure time.
    var firstTransitDepartureTime: Date? {
        if let journeySummary { return journeySummary.firstBoarding ?? journeySummary.departure }
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
        if let journeySummary { return journeySummary.departure }
        return plan.legs.first.flatMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }
    }

    /// Arrival time at the destination, preferring realtime over scheduled.
    var arrivalTime: Date? {
        if let journeySummary { return journeySummary.arrival }
        return plan.legs.compactMap {
            $0.realtimeArrivalTime ?? $0.scheduledArrivalTime ?? $0.arrivalTime
        }.last
    }

    /// Number of transfers between transit legs (always `>= 0`).
    var transferCount: Int {
        journeySummary?.transferCount ?? max(0, transitLegs.filter { $0.continuesInSeatFromTripID == nil }.count - 1)
    }

    /// Effective time available between each pair of consecutive transit legs.
    ///
    /// A walking leg between rides is intentionally not inspected directly: the
    /// gap from the preceding ride's arrival to the following ride's departure
    /// already includes the time spent making that transfer. `nil` means at
    /// least one transfer is missing timing data; a direct route returns `[]`.
    var transferGapDurations: [TimeInterval]? {
        if let journeySummary { return journeySummary.transferGaps }
        let legs = transitLegs
        guard legs.count > 1 else { return [] }

        var gaps: [TimeInterval] = []
        gaps.reserveCapacity(legs.count - 1)
        for (arrivingLeg, departingLeg) in zip(legs, legs.dropFirst()) {
            if departingLeg.continuesInSeatFromTripID != nil { continue }
            guard let arrival = Self.effectiveArrivalTime(for: arrivingLeg),
                  let departure = Self.effectiveDepartureTime(for: departingLeg)
            else {
                return nil
            }
            gaps.append(departure.timeIntervalSince(arrival))
        }
        return gaps
    }

    /// The tightest connection in the route. Negative values represent a
    /// connection that is already missed according to the effective times.
    var minimumTransferGapDuration: TimeInterval? {
        transferGapDurations?.min()
    }

    /// Only an actual change with less than two minutes available is tight.
    /// Use effective times so old feed-buffer warnings cannot revive the pill.
    var hasTightTransfer: Bool {
        transferGapDurations?.contains { $0 >= 0 && $0 < 120 } == true
    }

    /// Total effective time spent between transit legs.
    var totalTransferGapDuration: TimeInterval? {
        transferGapDurations?.reduce(0, +)
    }

    /// Distinct line labels used by the option, in order.
    var routeNames: [String] {
        var seen: Set<String> = []
        return transitLegs.compactMap(\.routeName).filter { seen.insert($0).inserted }
    }

    /// `true` when any transit leg carries realtime information.
    var usesLiveData: Bool {
        if let statusEvidence { return statusEvidence.coverage != .scheduleOnly }
        return transitLegs.contains { leg in
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
        if let statusEvidence {
            return RouteRealtimeCoverage(rawValue: statusEvidence.coverage.rawValue) ?? .scheduleOnly
        }
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

    /// True when the complete door-to-door journey is made on foot.
    var isWalkingOnly: Bool {
        !plan.legs.isEmpty && plan.legs.allSatisfy { $0.transportKind == .walking }
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
        if let journeySummary { return journeySummary.walkingDistance }
        return plan.legs
            .filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    /// True when any leg endpoint lies outside Luxembourg's bounding box — the
    /// journey likely crosses into France, Germany, or Belgium, where ATP
    /// real-time coverage of CFL/SNCF/DB connections may be incomplete.
    var crossesBorder: Bool {
        if let journeySummary { return journeySummary.crossesBorder }
        func insideLuxembourg(_ point: LocationPoint) -> Bool {
            (49.44 ... 50.19).contains(point.latitude) && (5.73 ... 6.54).contains(point.longitude)
        }
        return plan.legs.contains { !insideLuxembourg($0.origin) || !insideLuxembourg($0.destination) }
    }

    private static func effectiveDepartureTime(for leg: RoutePlan.Leg) -> Date? {
        leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
    }

    private static func effectiveArrivalTime(for leg: RoutePlan.Leg) -> Date? {
        leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
    }

    /// Resolves the option's status relative to a reference time.
    ///
    /// Resolution order: cancelled → missed (transit first departure already
    /// gone, with a 30s grace) → Connection miss → at-risk (any tight
    /// transfer) → delayed → live / partly-live / schedule-only. Vel'OH!-only
    /// plans never become missed.
    ///
    /// - Parameter now: The reference time, usually the current date.
    func status(at now: Date) -> RouteOptionStatus {
        let stored = statusEvidence
        let evidence = JourneyStatusEvidence(
            firstBoarding: stored?.firstBoarding ?? (isVelohOnly ? nil : firstTransitDepartureTime),
            cancelled: stored?.cancelled ?? transitLegs.contains { $0.liveStatus == .cancelled },
            delayed: stored?.delayed ?? transitLegs.contains { ($0.delayMinutes ?? 0) > 0 },
            tightTransfer: hasTightTransfer,
            connectionMiss: stored?.connectionMiss ?? transitLegs.contains { $0.transferWarning == "Connection miss" },
            coverage: stored?.coverage ?? JourneyRealtimeCoverage(rawValue: realtimeCoverage.rawValue) ?? .scheduleOnly)
        return RouteOptionStatus(rawValue: evidence.status(at: now, feasibility: feasibility).rawValue)
            ?? .scheduledOnly
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
    /// One or more legs currently have a positive live delay.
    case delayed
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

    /// Whether the package considers the option usable for selection.
    var isSelectable: Bool {
        JourneyStatus(rawValue: rawValue)?.isSelectable ?? false
    }

    /// Short label suitable for a badge.
    var displayText: String {
        switch self {
        case .viable: "Live"
        case .delayed: "Delayed"
        case .partiallyLive: "Partly live"
        case .scheduledOnly: "Schedule only"
        case .atRisk: "Tight transfer"
        case .connectionMayBeMissed: "Connection miss"
        case .missed: "Missed"
        case .cancelled: "Cancelled"
        }
    }
}
