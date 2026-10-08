import SwiftUI

/// Presentation of a transit leg's known live status in route line badges.
enum RouteLineStatus {
    case onTime
    case delayed
    case cancelled

    init?(leg: RoutePlan.Leg) {
        guard leg.transportKind == .transit else { return nil }
        switch leg.liveStatus {
        case .live:
            self = (leg.delayMinutes ?? 0) > 0 ? .delayed : .onTime
        case .delayed:
            self = .delayed
        case .cancelled:
            self = .cancelled
        case .scheduled, .unknown:
            return nil
        }
    }

    var color: Color {
        switch self {
        case .onTime: Color(red: 0.55, green: 0.85, blue: 0.55)
        case .delayed: .yellow
        case .cancelled: .red
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark"
        case .delayed: "clock"
        case .cancelled: "xmark"
        }
    }

    var displayText: String {
        switch self {
        case .onTime: String(localized: "On time")
        case .delayed: String(localized: "Delayed")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    static func accessibilityDescription(for leg: RoutePlan.Leg) -> String {
        let name = leg.routeName ?? leg.mode.displayName
        let line = "\(leg.mode.displayName) \(name)"
        guard let status = Self(leg: leg) else { return line }
        return "\(line), \(status.displayText)"
    }
}
