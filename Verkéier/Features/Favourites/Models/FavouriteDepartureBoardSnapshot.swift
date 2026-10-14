import Foundation

enum FavouriteDepartureBoardPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

/// The latest departure board fetched for one favourite stop.
struct FavouriteDepartureBoardSnapshot {
    var phase: FavouriteDepartureBoardPhase = .idle
    var departures: [Departure] = []
    var lastUpdated: Date?
    var errorMessage: String?
}
