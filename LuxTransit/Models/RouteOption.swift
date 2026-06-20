import Foundation

nonisolated struct RouteOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let plan: RoutePlan
    let mapOverlay: RouteMapOverlay?

    var transitLegs: [RoutePlan.Leg] {
        plan.legs.filter { $0.transportKind == .transit }
    }

    var firstTransitDepartureTime: Date? {
        transitLegs.compactMap {
            $0.realtimeDepartureTime ?? $0.scheduledDepartureTime ?? $0.departureTime
        }.min()
    }

    var arrivalTime: Date? {
        plan.legs.compactMap {
            $0.realtimeArrivalTime ?? $0.scheduledArrivalTime ?? $0.arrivalTime
        }.last
    }

    var transferCount: Int {
        max(0, transitLegs.count - 1)
    }

    var routeNames: [String] {
        var seen: Set<String> = []
        return transitLegs.compactMap(\.routeName).filter { seen.insert($0).inserted }
    }

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

    var walkingDistanceMeters: Double {
        plan.legs
            .filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

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

nonisolated enum RouteOptionStatus: String, Codable, Hashable, Sendable {
    case viable
    case scheduledOnly
    case atRisk
    case missed
    case cancelled

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
