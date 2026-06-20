import Foundation

enum DebugTransitDataMode: String, CaseIterable, Identifiable, Sendable {
    case normal
    case sample
    case empty
    case failure
    case disruption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .sample: "Sample"
        case .empty: "Empty"
        case .failure: "Failure"
        case .disruption: "Disruption"
        }
    }

    var detail: String {
        switch self {
        case .normal:
            "Use live or configured production-like services."
        case .sample:
            "Show sample nearby stops, departures, and stable mock alerts."
        case .empty:
            "Force empty nearby, departure, and alert states."
        case .failure:
            "Force loading failures for nearby stops, departures, and alerts."
        case .disruption:
            "Use sample departures with severe service disruptions."
        }
    }
}
