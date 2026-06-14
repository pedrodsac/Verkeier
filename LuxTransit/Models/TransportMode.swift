import Foundation

enum TransportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case train
    case tram
    case bus
    case funicular
    case walking
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .train: "Train"
        case .tram: "Tram"
        case .bus: "Bus"
        case .funicular: "Funicular"
        case .walking: "Walking"
        case .unknown: "Unknown"
        }
    }
}
