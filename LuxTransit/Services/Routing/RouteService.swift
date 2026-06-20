import Foundation

protocol RouteService: Sendable {
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}

enum RoutingError: Error, Equatable {
    case noRouteFound
    case timetableUnavailable
    case noPublicTransportRoute
}
