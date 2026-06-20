import Foundation

struct EmptyATPClient: ATPClient {
    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        []
    }

    nonisolated func departureBoard(stopId: String) async throws -> [Departure] {
        []
    }

    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure] {
        []
    }
}
