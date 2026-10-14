import Foundation
import MobiliteitKit

/// Uses only the active immutable OSM pedestrian graph. A replacement is picked up on
/// the next request without ever modifying an engine's open tile archive.
actor LocalFirstWalkingRouter: WalkingRouting {
    private let datasetManager: RoutingDatasetManager
    private struct RouterPool {
        let version: String
        var routers: [ValhallaWalkingRouter]
        var activeCounts: [Int]
    }
    private let measuredRoutes = MeasuredWalkingRouteCache()
    private var routerPool: RouterPool?
    // Each native instance remains serialized. Independent instances allow
    // the bounded four-request transfer batch to use four cores.
    private let maximumLocalRouters = 4

    init(datasetManager: RoutingDatasetManager) {
        self.datasetManager = datasetManager
    }

    func checkAvailability() async throws {
        _ = try await withLocalRouter { _ in true }
    }

    /// Opens the installed graph before the first route tap. Graph startup is
    /// local work, but doing it on the request path can exhaust the UI deadline.
    func prepareLocalGraph() async {
        _ = try? await withLocalRouter { _ in true }
    }

    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        guard !destinations.isEmpty else { return [] }
        var results: [OfflineWalkingEstimate] = []
        for destination in destinations {
            try Task.checkCancellation()
            do {
                let path = try await route(from: origin, to: destination.location)
                results.append(.init(destinationID: destination.id, distanceMeters: path.distanceMeters,
                                     duration: path.duration, source: path.source))
            } catch WalkingRoutingError.noRoute { continue }
        }
        return results
    }

    func estimates(
        from origins: [WalkingOrigin],
        to destination: LocationPoint
    ) async throws -> [OfflineWalkingEstimate] {
        guard !origins.isEmpty else { return [] }
        var results: [OfflineWalkingEstimate] = []
        for origin in origins {
            try Task.checkCancellation()
            do {
                let path = try await route(from: origin.location, to: destination)
                results.append(.init(destinationID: origin.id, distanceMeters: path.distanceMeters,
                                     duration: path.duration, source: path.source))
            } catch WalkingRoutingError.noRoute { continue }
        }
        return results
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        guard let dataset = try await datasetManager.activeDataset() else { throw WalkingRoutingError.datasetUnavailable }
        return try await route(from: origin, to: destination, dataset: dataset)
    }

    func routes(_ requests: [OfflineWalkingRequest], maximumConcurrency: Int) async -> [OfflineWalkingRoute?] {
        guard !requests.isEmpty else { return [] }
        guard let dataset = try? await datasetManager.activeDataset() else {
            return Array(repeating: nil, count: requests.count)
        }
        // One immutable graph revision for the whole batch. Checking the
        // current/manifest/archive files for every pair repeated thousands of
        // filesystem operations inside each walking-transfer round.
        return await WalkingRouteBatch.resolve(requests, maximumConcurrency: maximumConcurrency) {
            try await self.route(from: $0.from, to: $0.to, dataset: dataset, preferShortSearch: true)
        }
    }

    private func route(from origin: LocationPoint, to destination: LocationPoint,
                       dataset: RoutingDataset, preferShortSearch: Bool = false) async throws -> OfflineWalkingRoute {
        return try await measuredRoutes.route(from: origin, to: destination, revision: Self.revision(dataset)) {
            try await self.uncachedRoute(from: origin, to: destination, dataset: dataset, preferShortSearch: preferShortSearch)
        }
    }

    func cacheRevision() async -> String? {
        guard let dataset = try? await datasetManager.activeDataset() else { return nil }
        return Self.revision(dataset)
    }

    private static func revision(_ dataset: RoutingDataset) -> String {
        "\(dataset.revision)|\(PafendallFunicularConnection.revision)"
    }

    private func uncachedRoute(from: LocationPoint, to: LocationPoint, dataset: RoutingDataset,
                               preferShortSearch: Bool = false) async throws -> OfflineWalkingRoute {
        let direct = try? await pedestrianRoute(from: from, to: to, dataset: dataset, preferShortSearch: preferShortSearch)
        try Task.checkCancellation()
        if let connection = try? await PafendallFunicularConnection.route(from: from, to: to, pedestrian: {
            try await self.pedestrianRoute(from: $0, to: $1, dataset: dataset)
        }), direct == nil || connection.duration < direct!.duration {
            return connection
        }
        try Task.checkCancellation()
        guard let direct else { throw WalkingRoutingError.noRoute }
        return direct
    }

    private func pedestrianRoute(from: LocationPoint, to: LocationPoint, dataset: RoutingDataset,
                                 preferShortSearch: Bool = false) async throws -> OfflineWalkingRoute {
        calibrated(try await withLocalRouter(dataset: dataset) {
            if preferShortSearch { return try await $0.shortRoute(from: from, to: to) }
            return try await $0.route(from: from, to: to)
        })
    }

    private func withLocalRouter<Value: Sendable>(
        dataset selectedDataset: RoutingDataset? = nil,
        _ operation: @Sendable (ValhallaWalkingRouter) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let dataset: RoutingDataset
        if let selectedDataset { dataset = selectedDataset }
        else {
            guard let active = try await datasetManager.activeDataset() else {
                throw WalkingRoutingError.datasetUnavailable
            }
            dataset = active
        }
        if routerPool?.version != dataset.revision {
            routerPool = RouterPool(version: dataset.revision, routers: [], activeCounts: [])
        }
        guard var pool = routerPool else { throw WalkingRoutingError.datasetUnavailable }
        let leastBusy = pool.activeCounts.enumerated().min { $0.element < $1.element }
        let index: Int
        if pool.routers.isEmpty {
            let router = try ValhallaWalkingRouter(
                tileArchiveURL: dataset.tileArchiveURL,
                datasetVersion: "\(dataset.version)-pool-0"
            )
            pool.routers.append(router)
            pool.activeCounts.append(0)
            index = 0
        } else if pool.routers.count < maximumLocalRouters,
                  (leastBusy?.element ?? 0) > 0,
                  let router = try? ValhallaWalkingRouter(
                    tileArchiveURL: dataset.tileArchiveURL,
                    datasetVersion: "\(dataset.version)-pool-\(pool.routers.count)"
                  ) {
            index = pool.routers.count
            pool.routers.append(router)
            pool.activeCounts.append(0)
        } else {
            index = leastBusy?.offset ?? 0
        }
        pool.activeCounts[index] += 1
        let router = pool.routers[index]
        routerPool = pool
        defer {
            if routerPool?.version == dataset.revision,
               routerPool?.activeCounts.indices.contains(index) == true {
                routerPool?.activeCounts[index] -= 1
            }
        }
        try Task.checkCancellation()
        return try await operation(router)
    }

    private func calibrated(_ route: OfflineWalkingRoute) -> OfflineWalkingRoute {
        OfflineWalkingRoute(
            distanceMeters: route.distanceMeters,
            duration: WalkingDurationCalibration.adjusted(route.duration),
            coordinates: route.coordinates,
            source: route.source
        )
    }
}
