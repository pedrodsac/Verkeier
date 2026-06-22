import Foundation

/// Access to live transit data from the mobiliteit.lu (ATP) OpenAPI.
///
/// This is the seam for realtime departures and nearby stops. Production uses
/// `LiveATPClient` (gated behind `ATP_ACCESS_ID`); previews and early phases use
/// `EmptyATPClient`/`ATPMockClient`. Inject an implementation via the
/// environment rather than constructing one in a view.
protocol ATPClient: Sendable {
    /// Fetches stops near a coordinate.
    /// - Parameters:
    ///   - latitude: Latitude of the search centre.
    ///   - longitude: Longitude of the search centre.
    /// - Returns: Nearby stops, ordered by the feed's proximity ranking.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]

    /// Fetches the departure board for a single stop or platform.
    /// - Parameter stopId: The stop/platform identifier to query.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func departureBoard(stopId: String) async throws -> [Departure]

    /// Fetches and merges departure boards for several stops/platforms.
    ///
    /// The default implementation normalizes the ids, queries each in turn, and
    /// merges duplicate departures via `ATPMapper`.
    /// - Parameter stopIds: The stop/platform identifiers to query.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure]
}

extension ATPClient {
    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure] {
        var departures: [Departure] = []

        for stopId in ATPStopIdentifier.normalized(stopIds) {
            departures.append(contentsOf: try await departureBoard(stopId: stopId))
        }

        return ATPMapper.mergedDepartures(departures)
    }
}

/// Errors thrown by an ``ATPClient``.
enum ATPClientError: Error, Equatable {
    /// No `ATP_ACCESS_ID` is configured, so live requests cannot be made.
    case missingAccessId
    /// The response body was missing or could not be decoded.
    case invalidResponse
    /// The server returned a non-success HTTP status.
    case httpStatus(Int)
    /// Every per-platform request for a multi-platform stop failed.
    case allPlatformRequestsFailed
}

/// Helpers for normalizing ATP stop/platform identifiers.
enum ATPStopIdentifier {
    /// Trims whitespace, drops blanks, and removes duplicates while preserving
    /// order.
    nonisolated static func normalized(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
