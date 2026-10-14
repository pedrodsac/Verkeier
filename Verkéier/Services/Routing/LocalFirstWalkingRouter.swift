import Foundation
import MobiliteitKit
import OSLog

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
    private let transferWalkStore: TransferWalkStore?
    private let transferWalkMode: TransferWalkMode
    private var transferWalks: (revision: String, table: TransferWalkTable?)?
    private var transferWalkHits = 0
    private var transferWalkMisses = 0

    init(
        datasetManager: RoutingDatasetManager,
        transferWalkStore: TransferWalkStore? = nil,
        transferWalkMode: TransferWalkMode = TransferWalkSettings.mode
    ) {
        self.datasetManager = datasetManager
        self.transferWalkStore = transferWalkStore
        self.transferWalkMode = transferWalkMode
    }

    func checkAvailability() async throws {
        _ = try await withLocalRouter { _ in true }
    }

    /// Opens the installed graph before the first route tap. Graph startup is
    /// local work, but doing it on the request path can exhaust the UI deadline.
    func prepareLocalGraph() async {
        _ = try? await withLocalRouter { _ in true }
        if let dataset = try? await datasetManager.activeDataset() { _ = transferWalkTable(for: dataset) }
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
                results.append(
                    .init(
                        destinationID: destination.id,
                        distanceMeters: path.distanceMeters,
                        duration: path.duration,
                        source: path.source
                    )
                )
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
                results.append(
                    .init(
                        destinationID: origin.id,
                        distanceMeters: path.distanceMeters,
                        duration: path.duration,
                        source: path.source
                    )
                )
            } catch WalkingRoutingError.noRoute { continue }
        }
        return results
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        guard let dataset = try await datasetManager.activeDataset() else {
            throw WalkingRoutingError.datasetUnavailable
        }
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
        let table = transferWalkTable(for: dataset)
        return await WalkingRouteBatch.resolve(requests, maximumConcurrency: maximumConcurrency) {
            try await self.route(from: $0.from, to: $0.to, dataset: dataset, preferShortSearch: true, table: table)
        }
    }

    private func route(
        from origin: LocationPoint,
        to destination: LocationPoint,
        dataset: RoutingDataset,
        preferShortSearch: Bool = false,
        table: TransferWalkTable? = nil
    ) async throws -> OfflineWalkingRoute {
        return try await measuredRoutes.route(from: origin, to: destination, revision: Self.revision(dataset)) {
            try await self.calculatedRoute(
                from: origin,
                to: destination,
                dataset: dataset,
                preferShortSearch: preferShortSearch,
                table: table
            )
        }
    }

    /// The deterministic computation behind the measured cache. A stored transfer
    /// walk replaces only this computation, so cache keys, ordering and the
    /// short/full-search race stay exactly as they are without the table.
    private func calculatedRoute(
        from: LocationPoint,
        to: LocationPoint,
        dataset: RoutingDataset,
        preferShortSearch: Bool,
        table: TransferWalkTable?
    ) async throws -> OfflineWalkingRoute {
        guard preferShortSearch, let table, from.name == nil, to.name == nil,
            let stored = table.outcome(for: TransferWalkKey(from: from, to: to))
        else {
            if preferShortSearch, table != nil { transferWalkMisses += 1 }
            return try await uncachedRoute(from: from, to: to, dataset: dataset, preferShortSearch: preferShortSearch)
        }
        try Task.checkCancellation()
        if transferWalkMode == .verify { return try await verified(stored, from: from, to: to, dataset: dataset) }
        transferWalkHits += 1
        switch stored {
        case .route(let route): return route
        case .noRoute: throw WalkingRoutingError.noRoute
        }
    }

    /// Debug and benchmark builds only: recompute live and compare with the table.
    private func verified(
        _ stored: TransferWalkOutcome,
        from: LocationPoint,
        to: LocationPoint,
        dataset: RoutingDataset
    ) async throws -> OfflineWalkingRoute {
        let live: TransferWalkOutcome
        do {
            live = .route(try await uncachedRoute(from: from, to: to, dataset: dataset, preferShortSearch: true))
        } catch WalkingRoutingError.noRoute { live = .noRoute }
        if live != stored {
            Logger(subsystem: "dev.pedrocordeiro.Verkeier", category: "TransferWalks")
                .fault(
                    "Stored transfer walk differs from the live computation for \(from.latitude),\(from.longitude) to \(to.latitude),\(to.longitude)"
                )
            assertionFailure("Stored transfer walk differs from the live computation")
        }
        transferWalkHits += 1
        switch live {
        case .route(let route): return route
        case .noRoute: throw WalkingRoutingError.noRoute
        }
    }

    // MARK: Stored transfer walks

    /// Loads the stored table once per walking graph. A table built for another
    /// graph is ignored but kept; a table that fails validation is removed, but
    /// only if it is still the exact file that failed.
    private func transferWalkTable(for dataset: RoutingDataset) -> TransferWalkTable? {
        guard transferWalkMode != .off, let store = transferWalkStore else { return nil }
        if let transferWalks, transferWalks.revision == dataset.revision { return transferWalks.table }
        var table: TransferWalkTable?
        switch store.load() {
        case .table(let loaded) where loaded.graphIdentity == dataset.transferWalkIdentity.value: table = loaded
        case .invalid(let stamp): store.discard(ifStillMatching: stamp)
        case .table, .missing, .unreadable: break
        }
        transferWalks = (dataset.revision, table)
        return table
    }

    func transferWalkStatistics() -> (hits: Int, misses: Int) { (transferWalkHits, transferWalkMisses) }

    func cacheRevision() async -> String? {
        guard let dataset = try? await datasetManager.activeDataset() else { return nil }
        return Self.revision(dataset)
    }

    private static func revision(_ dataset: RoutingDataset) -> String {
        "\(dataset.revision)|\(PafendallFunicularConnection.revision)"
    }

    /// `strict` is used only when building the stored table: it rethrows any
    /// failure that is not a deterministic routing failure instead of treating
    /// it as "no route". Without it the behaviour is the original `try?` flow.
    private func uncachedRoute(
        from: LocationPoint,
        to: LocationPoint,
        dataset: RoutingDataset,
        preferShortSearch: Bool = false,
        strict: Bool = false
    ) async throws -> OfflineWalkingRoute {
        let direct: OfflineWalkingRoute?
        do {
            direct = try await pedestrianRoute(
                from: from,
                to: to,
                dataset: dataset,
                preferShortSearch: preferShortSearch
            )
        } catch let error where strict && !TransferWalkErrorClassifier.isDeterministic(error) {
            throw error
        } catch {
            direct = nil
        }
        try Task.checkCancellation()
        let connection: OfflineWalkingRoute?
        do {
            connection = try await PafendallFunicularConnection.route(
                from: from,
                to: to,
                pedestrian: {
                    try await self.pedestrianRoute(from: $0, to: $1, dataset: dataset)
                }
            )
        } catch let error where strict && !TransferWalkErrorClassifier.isDeterministic(error) {
            throw error
        } catch {
            connection = nil
        }
        if let connection, direct == nil || connection.duration < direct!.duration {
            return connection
        }
        try Task.checkCancellation()
        guard let direct else { throw WalkingRoutingError.noRoute }
        return direct
    }

    private func pedestrianRoute(
        from: LocationPoint,
        to: LocationPoint,
        dataset: RoutingDataset,
        preferShortSearch: Bool = false
    ) async throws -> OfflineWalkingRoute {
        calibrated(
            try await withLocalRouter(dataset: dataset) {
                if preferShortSearch { return try await $0.shortRoute(from: from, to: to) }
                return try await $0.route(from: from, to: to)
            }
        )
    }

    private func withLocalRouter<Value: Sendable>(
        dataset selectedDataset: RoutingDataset? = nil,
        _ operation: @Sendable (ValhallaWalkingRouter) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let dataset: RoutingDataset
        if let selectedDataset {
            dataset = selectedDataset
        } else {
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
            )
        {
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
                routerPool?.activeCounts.indices.contains(index) == true
            {
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

    // MARK: Transfer walk computation

    func prepareTransferWalkComputation() async throws -> RoutingDataset {
        guard let dataset = try await datasetManager.activeDataset() else {
            throw WalkingRoutingError.datasetUnavailable
        }
        // Open the first native router now, so later pool calls cannot fail on creation.
        _ = try await withLocalRouter(dataset: dataset) { _ in true }
        return dataset
    }

    func transferWalkOutcome(
        from: LocationPoint,
        to: LocationPoint,
        dataset: RoutingDataset
    ) async throws -> TransferWalkOutcome {
        do {
            let route = try await uncachedRoute(
                from: from,
                to: to,
                dataset: dataset,
                preferShortSearch: true,
                strict: true
            )
            guard route.segments.isEmpty, route.source == .localOSM else {
                throw TransferWalkTableError.unsupported("station connection")
            }
            return .route(route)
        } catch WalkingRoutingError.noRoute {
            return .noRoute
        }
    }

    func isActiveDataset(_ dataset: RoutingDataset) async -> Bool {
        (try? await datasetManager.activeDataset())?.revision == dataset.revision
    }

    /// Makes a freshly written table live for the running router.
    func adoptTransferWalks(_ table: TransferWalkTable) async {
        guard transferWalkMode != .off, let dataset = try? await datasetManager.activeDataset(),
            table.graphIdentity == dataset.transferWalkIdentity.value
        else { return }
        transferWalks = (dataset.revision, table)
    }
}
