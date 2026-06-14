import Foundation

protocol ATPClient: Sendable {
    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]
    func departureBoard(stopId: String) async throws -> [Departure]
}

enum ATPClientError: Error, Equatable {
    case missingAccessId
    case invalidResponse
    case httpStatus(Int)
}
