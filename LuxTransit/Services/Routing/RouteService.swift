import Foundation

/// Computes journeys between two places and hands off to Apple Maps.
///
/// `PublicTransportRouteService` is the production implementation, combining the
/// GTFS timetable with live ATP data; `MapKitRouteService` provides a
/// MapKit-only fallback. Inject an implementation via the environment.
protocol RouteService: Sendable {
    /// Computes route alternatives between two points.
    /// - Parameters:
    ///   - from: Journey origin.
    ///   - to: Journey destination.
    /// - Returns: A ``RouteCalculation`` holding one or more options.
    /// - Throws: ``RoutingError`` when no usable route can be produced.
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation

    /// Opens the journey in Apple Maps for turn-by-turn navigation.
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}

/// Errors thrown by a ``RouteService``.
enum RoutingError: Error, Equatable {
    /// No route of any kind could be found between the points.
    case noRouteFound
    /// The offline timetable needed for planning was unavailable.
    case timetableUnavailable
    /// A route exists but none of it uses public transport.
    case noPublicTransportRoute
}
