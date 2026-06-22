import Foundation

/// Access to Ville de Luxembourg AVL service-disruption messages.
///
/// Production uses `LiveAVLClient` (parsing the AVL XML feed); previews and
/// tests use `MockAVLClient`. Inject an implementation via the environment.
protocol AVLClient: Sendable {
    /// Fetches the current disruption / information messages.
    /// - Throws: ``AVLClientError`` on a bad URL, transport, or HTTP failure.
    nonisolated func fetchMessages() async throws -> [AlertMessage]
}

/// Errors thrown by an ``AVLClient``.
enum AVLClientError: Error {
    /// The configured feed URL was invalid.
    case invalidURL
    /// The response body was missing or could not be parsed.
    case invalidResponse
    /// The server returned a non-success HTTP status.
    case httpStatus(Int)
}
