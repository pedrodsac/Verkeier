import Foundation

protocol RouteService: Sendable {
    func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation
    func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}
