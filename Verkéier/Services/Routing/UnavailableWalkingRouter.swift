import Foundation

/// An unconfigured environment must never silently request an external walk.
nonisolated struct UnavailableWalkingRouter: WalkingRouting {
    func checkAvailability() async throws { throw WalkingRoutingError.datasetUnavailable }

    func estimates(from: LocationPoint, to destinations: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        guard !destinations.isEmpty else { return [] }
        throw WalkingRoutingError.datasetUnavailable
    }

    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        throw WalkingRoutingError.datasetUnavailable
    }
}
