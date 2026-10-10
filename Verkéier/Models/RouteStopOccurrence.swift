import Foundation

/// One visit to a stop, rather than the physical stop's identity alone.
nonisolated struct RouteStopOccurrence: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let stopID: String?
    let name: String
    let coordinate: RouteMapCoordinate
}
