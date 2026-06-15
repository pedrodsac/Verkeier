import Foundation

protocol ATPClient: Sendable {
    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]
    func departureBoard(stopId: String) async throws -> [Departure]
    func departureBoards(stopIds: [String]) async throws -> [Departure]
}

extension ATPClient {
    func departureBoards(stopIds: [String]) async throws -> [Departure] {
        var departures: [Departure] = []

        for stopId in ATPStopIdentifier.normalized(stopIds) {
            departures.append(contentsOf: try await departureBoard(stopId: stopId))
        }

        return ATPMapper.mergedDepartures(departures)
    }
}

enum ATPClientError: Error, Equatable {
    case missingAccessId
    case invalidResponse
    case httpStatus(Int)
    case allPlatformRequestsFailed
}

enum ATPStopIdentifier {
    static func normalized(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
