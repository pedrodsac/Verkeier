import Foundation

/// Filter state retained by the stop-detail UI and favourite stops.
nonisolated struct TransitBoardFilter: Codable, Hashable, Sendable {
    var products: Int? = nil
    var operators: [String] = []
    var destinationStopID: String? = nil
    var platforms: [String] = []
    var durationMinutes = 120
    var maximumJourneys = 20
    var realtimeMode: TransitRealtimeMode = .full
}

nonisolated enum TransitRealtimeMode: String, Codable, CaseIterable, Sendable {
    case full = "FULL"
    case off = "OFF"
}

/// A scheduled GTFS departure kept separate from a live HAFAS board.
struct OfflineScheduleDeparture: Identifiable, Equatable, Sendable {
    let id: String
    let lineName: String
    let destination: String
    let departureDate: Date
    let platform: String?
    let mode: TransportMode
}

extension String {
    nonisolated var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
