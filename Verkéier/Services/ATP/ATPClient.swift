import Foundation

/// Access to live transit data from the mobiliteit.lu (ATP) OpenAPI.
///
/// This is the seam for realtime departures and nearby stops. Production uses
/// `LiveATPClient` through the configured API proxy; previews and early phases
/// use `EmptyATPClient`/`ATPMockClient`. Inject an implementation via the
/// environment rather than constructing one in a view.
protocol ATPClient: Sendable {
    nonisolated func routingBoard(stopID: String, options: ATPDepartureBoardOptions) async throws -> ATPRoutingBoard

    /// Fetches stops near a coordinate.
    /// - Parameters:
    ///   - latitude: Latitude of the search centre.
    ///   - longitude: Longitude of the search centre.
    /// - Returns: Nearby stops, ordered by the feed's proximity ranking.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]

    /// Fetches nearby stops with an explicit bounded query scope. Existing
    /// clients only need to implement the unfiltered method.
    nonisolated func nearbyStops(
        latitude: Double,
        longitude: Double,
        options: ATPNearbyStopsOptions
    ) async throws -> [Stop]

    /// Fetches the departure board for a single stop or platform.
    /// - Parameter stopId: The stop/platform identifier to query.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func departureBoard(stopId: String) async throws -> [Departure]

    /// Fetches a departure board with server-side filters.
    nonisolated func departureBoard(stopId: String, options: ATPDepartureBoardOptions) async throws -> [Departure]

    /// Fetches and merges departure boards for several stops/platforms.
    ///
    /// The default implementation normalizes the ids, queries each in turn, and
    /// merges duplicate departures via `ATPMapper`.
    /// - Parameter stopIds: The stop/platform identifiers to query.
    /// - Throws: ``ATPClientError`` on auth, transport, or decoding failure.
    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure]

    nonisolated func departureBoards(
        stopIds: [String],
        options: ATPDepartureBoardOptions
    ) async throws -> [Departure]

    /// Fetches the arrival board for a stop (vehicles arriving, for riders
    /// waiting to meet someone). ATP exposes departures only today, so the
    /// default implementation returns an empty board.
    // ponytail: stubbed — wire when an ATP arrivals feed is confirmed.
    nonisolated func arrivalBoard(stopId: String) async throws -> [Departure]
}

extension ATPClient {
    nonisolated func routingBoard(stopID: String, options: ATPDepartureBoardOptions) async throws -> ATPRoutingBoard {
        let departures = try await departureBoard(stopId: stopID, options: options)
        return ATPRoutingBoard(journeys: departures.map { ATPRoutingJourney(departure: $0) })
    }

    nonisolated func nearbyStops(
        latitude: Double,
        longitude: Double,
        options _: ATPNearbyStopsOptions
    ) async throws -> [Stop] {
        try await nearbyStops(latitude: latitude, longitude: longitude)
    }

    nonisolated func departureBoard(
        stopId: String,
        options _: ATPDepartureBoardOptions
    ) async throws -> [Departure] {
        try await departureBoard(stopId: stopId)
    }

    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure] {
        try await departureBoards(stopIds: stopIds, options: ATPDepartureBoardOptions())
    }

    nonisolated func departureBoards(
        stopIds: [String],
        options: ATPDepartureBoardOptions
    ) async throws -> [Departure] {
        var departures: [Departure] = []

        for stopId in ATPStopIdentifier.normalized(stopIds) {
            try await departures.append(contentsOf: departureBoard(stopId: stopId, options: options))
        }

        return ATPMapper.mergedDepartures(departures)
    }

    // ponytail: stubbed — wire when an ATP arrivals feed is confirmed.
    nonisolated func arrivalBoard(stopId _: String) async throws -> [Departure] {
        []
    }
}

/// Errors thrown by an ``ATPClient``.
enum ATPClientError: Error, Equatable {
    /// Neither an API proxy nor a direct ATP access id is configured.
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
