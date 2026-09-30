import Foundation
import MobiliteitKit

/// Computes journeys between two places and hands off to Apple Maps.
///
/// Production transit calculation delegates to MobiliteitKit. Inject services
/// through the environment to supply fixtures or unavailable implementations.
protocol RouteService: Sendable {
    /// Computes route alternatives between two points.
    /// - Parameters:
    ///   - from: Journey origin.
    ///   - to: Journey destination.
    ///   - time: When the rider wants to travel (now / depart at / arrive by).
    ///   - filters: Rider constraints (sort / mode) applied while
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

    /// Publishes route options after one calculation. The default implementation
    /// publishes the complete result immediately.
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
    nonisolated func refinementEvents(
        in options: [RouteOption], context: RouteValidationContext?
    ) -> AsyncStream<WalkingRefinementEvent>
}

nonisolated enum WalkingRefinementEvent: Sendable {
    case option(RouteOption)
    case invalidated(String)
    case calculation(RouteCalculation)
}

extension WalkingRouteRefining {
    nonisolated func refinementEvents(
        in options: [RouteOption], context: RouteValidationContext?
    ) -> AsyncStream<WalkingRefinementEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await option in refineWalkingRouteUpdates(in: options) {
                    guard !Task.isCancelled else { break }
                    if let context {
                        let feasibility = RouteItineraryValidator.assess(option, context: context)
                        if feasibility.isInvalid {
                            continuation.yield(.invalidated(option.id))
                            continue
                        }
                        var valid = option
                        valid.feasibility = feasibility
                        continuation.yield(.option(valid))
                    } else {
                        continuation.yield(.option(option))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

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
                    let calculation = try await calculateRoute(
                        from: from,
                        to: to,
                        time: time,
                        filters: filters,
                        realtimeRefreshPolicy: realtimeRefreshPolicy,
                        page: page
                    )
                    try Task.checkCancellation()
                    continuation.yield(calculation)
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
    /// The local pedestrian graph needed for walking was unavailable.
    case walkingUnavailable
    /// A route exists but none of it uses public transport.
    case noPublicTransportRoute
    /// The route provider did not resolve within the UI's bounded wait.
    case requestTimedOut
}

/// Selects the portion of the departure profile returned by a route search.
/// Page boundaries use door-to-door departure and, when available, stable ID.
nonisolated enum RouteSearchPage: Hashable, Sendable {
    case initial
    case earlierAdjacent, laterAdjacent
    case earlier(than: Date, limit: Int)
    case later(than: Date, limit: Int)
    case earlierFrom(than: Date, id: String, limit: Int)
    case laterFrom(than: Date, id: String, limit: Int)

}
