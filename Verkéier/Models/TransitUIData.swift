import Foundation

/// Filter state retained by the stop-detail UI and favourite stops.
///
/// Transit data connections are currently disabled, but the UI keeps these
/// values so its controls and persisted favourites remain intact.
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

/// A scheduled departure value kept by the existing stop-detail presentation.
/// No schedule provider populates it while GTFS is disconnected.
struct OfflineScheduleDeparture: Identifiable, Equatable {
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
