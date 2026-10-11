import Foundation

/// A short walk needs a connected path between its actual endpoints.
/// Valhalla's default correlation probes 50 reachable graph nodes per candidate
/// edge, even though the following A* search proves the pair connected. Retry
/// that full correlation if the direct search fails or exceeds the short-walk limits.
nonisolated enum ShortWalkingRouteSearch {
    static func route(
        calculate: @Sendable (Int) async throws -> OfflineWalkingRoute
    ) async throws -> OfflineWalkingRoute {
        try Task.checkCancellation()
        do {
            let route = try await calculate(0)
            try Task.checkCancellation()
            if route.distanceMeters.isFinite, route.distanceMeters >= 0,
               route.duration.isFinite, route.duration >= 0,
               route.distanceMeters <= 1_500,
               WalkingDurationCalibration.adjusted(route.duration) <= 900 { return route }
        } catch is CancellationError { throw CancellationError() }
        catch { }
        try Task.checkCancellation()
        return try await calculate(50)
    }
}
