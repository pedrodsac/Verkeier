import Foundation

/// Computes journeys between two places and hands off to Apple Maps.
///
/// `MapKitRouteService` is the current implementation and delegates route
/// calculation to Apple Maps. Inject an implementation via the environment.
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
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation

    /// Publishes a usable initial route set and may subsequently refine it.
    /// Implementations without progressive routing use the single-result
    /// default supplied by ``RouteService``.
    nonisolated func routeCalculationUpdates(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error>

    /// Opens the journey in Apple Maps for turn-by-turn navigation.
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}

/// Optional post-processing for services that can replace fast local walking
/// estimates with pedestrian routes from a road-network provider.
protocol WalkingRouteRefining: Sendable {
    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption]

    /// Publishes each route option again as soon as one of its walking legs has
    /// been resolved by the road-routing provider. Implementations that only
    /// support all-at-once refinement get a compatibility default below.
    nonisolated func refineWalkingRouteUpdates(in options: [RouteOption]) -> AsyncStream<RouteOption>
}

extension WalkingRouteRefining {
    nonisolated func refineWalkingRouteUpdates(in options: [RouteOption]) -> AsyncStream<RouteOption> {
        AsyncStream { continuation in
            let task = Task {
                let refined = await refineWalkingRoutes(in: options)
                for option in refined {
                    guard !Task.isCancelled else { break }
                    continuation.yield(option)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

extension RouteService {
    nonisolated func routeCalculationUpdates(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await calculateRoute(
                        from: from,
                        to: to,
                        time: time,
                        filters: filters,
                        realtimeRefreshPolicy: realtimeRefreshPolicy,
                        page: page
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Default calculations use the initial route-search page and a recent
    /// realtime snapshot when the service has a live provider.
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
            realtimeRefreshPolicy: .useCache,
            page: .initial
        )
    }

    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy
    ) async throws -> RouteCalculation {
        try await calculateRoute(
            from: from,
            to: to,
            time: time,
            filters: filters,
            realtimeRefreshPolicy: realtimeRefreshPolicy,
            page: .initial
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

/// Controls the freshness requested by a route calculation.
/// MapKit-only routing may ignore this policy.
nonisolated enum RouteRealtimeRefreshPolicy: Hashable, Sendable {
    /// Prefer the fastest available scheduled result.
    case scheduleOnly
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
    /// The route provider did not resolve within the UI's bounded wait.
    case requestTimedOut
}

/// Selects the portion of the departure profile returned by a route search.
/// Page boundaries are exclusive door-to-door departure timestamps.
nonisolated enum RouteSearchPage: Hashable, Sendable {
    case initial
    case earlier(than: Date, limit: Int)
    case later(than: Date, limit: Int)

    var resultLimit: Int {
        switch self {
        case .initial:
            5
        case let .earlier(_, limit), let .later(_, limit):
            max(0, limit)
        }
    }

    var boundary: Date? {
        switch self {
        case .initial:
            nil
        case let .earlier(boundary, _), let .later(boundary, _):
            boundary
        }
    }
}
