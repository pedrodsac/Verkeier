import Foundation

/// A mode of transport, used to label stops, routes, and route-plan legs.
enum TransportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case train
    case tram
    case bus
    case funicular
    /// A shared bicycle leg.
    case bicycle
    /// An on-foot leg, used by the route planner for walking segments.
    case walking
    /// Mode could not be determined from the source feed.
    case unknown

    var id: String { rawValue }

    /// Localized, human-readable name for the mode.
    var displayName: String {
        switch self {
        case .train: "Train"
        case .tram: "Tram"
        case .bus: "Bus"
        case .funicular: "Funicular"
        case .bicycle: "Bike"
        case .walking: "Walking"
        case .unknown: "Unknown"
        }
    }
}
