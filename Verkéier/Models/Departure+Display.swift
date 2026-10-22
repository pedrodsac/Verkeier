import Foundation

extension Departure {
    /// The vehicle kind for presentation, from the feed-provided ``mode``.
    var lineKind: LineKind? {
        switch mode {
        case .tram: .tram
        case .train: .train
        case .bus, .funicular: .bus
        default: nil
        }
    }

    var displayDestination: String {
        destination.headsignDisplayName(isTram: mode == .tram)
    }
}
