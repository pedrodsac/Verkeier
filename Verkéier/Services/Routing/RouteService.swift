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
    ///   - time: When the rider wants to travel (now / depart at / arrive by).
    ///   - filters: Rider constraints (sort / mode / accessibility) applied while
    ///     planning so preferred-mode journeys survive truncation.
    /// - Returns: A ``RouteCalculation`` holding one or more options.
    /// - Throws: ``RoutingError`` when no usable route can be produced.
    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy
    ) async throws -> RouteCalculation

    /// Opens the journey in Apple Maps for turn-by-turn navigation.
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}

extension RouteService {
    /// Default calculation path: reuse a snapshot that is still fresh enough to be
    /// useful. The explicit planner refresh action passes `.forceRefresh` instead.
    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters
    ) async throws -> RouteCalculation {
        try await calculateRoute(
            from: from,
            to: to,
            time: time,
            filters: filters,
            realtimeRefreshPolicy: .useCache
        )
    }

    /// Convenience that plans for immediate departure with default filters.
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation {
        try await calculateRoute(from: from, to: to, time: .leaveNow, filters: RoutePlannerFilters())
    }

    /// Convenience that plans for the given time with default filters.
    nonisolated func calculateRoute(
        from: LocationPoint, to: LocationPoint, time: RoutePlanningTime
    ) async throws -> RouteCalculation {
        try await calculateRoute(from: from, to: to, time: time, filters: RoutePlannerFilters())
    }
}

/// Controls whether a planner calculation may reuse its short-lived ATP snapshot.
/// The policy has no effect on offline and MapKit-only routing.
nonisolated enum RouteRealtimeRefreshPolicy: Hashable, Sendable {
    case useCache
    case forceRefresh
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
