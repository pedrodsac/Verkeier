import Foundation

struct EmptyATPClient: ATPClient {
    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId: String) async throws -> [Departure] {
        []
    }

    func departureBoards(stopIds: [String]) async throws -> [Departure] {
        []
    }
}
