import Foundation

protocol AVLClient: Sendable {
    nonisolated func fetchMessages() async throws -> [AlertMessage]
}

enum AVLClientError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}
