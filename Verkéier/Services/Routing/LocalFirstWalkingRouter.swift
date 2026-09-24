import Foundation
import MobiliteitKit

/// Chooses the active immutable OSM graph first, then MapKit, then a clearly
/// identified straight-line approximation. A replacement graph is picked up on
/// the next request without ever modifying an engine's open tile archive.
actor LocalFirstWalkingRouter: WalkingRouting {
    private let datasetManager: RoutingDatasetManager
    private let mapKitFallback: any WalkingRouting
    private let straightLineFallback: any WalkingRouting
    private struct RouterPool {
        let version: String
        var routers: [ValhallaWalkingRouter]
        var activeCounts: [Int]
    }
    private var routerPool: RouterPool?
    // Each Valhalla actor serializes its own native calls. Open the second
    // instance only when another request is already using the first.
    private let maximumLocalRouters = 2

    init(
        datasetManager: RoutingDatasetManager,
        mapKitFallback: any WalkingRouting = MapKitWalkingRouter(),
        straightLineFallback: any WalkingRouting = StraightLineWalkingRouter()
    ) {
        self.datasetManager = datasetManager
        self.mapKitFallback = mapKitFallback
        self.straightLineFallback = straightLineFallback
    }

    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        guard !destinations.isEmpty else { return [] }
        do {
            let estimates = try await withLocalRouter {
                try await $0.estimates(from: origin, to: destinations)
            }
            debugLog("Walking estimates: using local OSM graph for \(destinations.count) destination(s).")
            return calibrated(estimates)
        } catch {
            debugLog("Walking estimates: local OSM graph failed (\(error)); falling back to MapKit.")
        }
        do {
            let estimates = try await mapKitFallback.estimates(from: origin, to: destinations)
            debugLog("Walking estimates: using MapKit fallback for \(destinations.count) destination(s).")
            return calibrated(estimates)
        } catch {
            debugLog("Walking estimates: MapKit fallback failed (\(error)); using straight-line estimate.")
        }
        debugLog("Walking estimates: using straight-line fallback for \(destinations.count) destination(s).")
        return calibrated(try await straightLineFallback.estimates(from: origin, to: destinations))
    }

    func estimates(
        from origins: [WalkingOrigin],
        to destination: LocationPoint
    ) async throws -> [OfflineWalkingEstimate] {
        guard !origins.isEmpty else { return [] }
        if let estimates = try? await withLocalRouter({
            try await $0.estimates(from: origins, to: destination)
        }) {
            return calibrated(estimates)
        }
        if let estimates = try? await mapKitFallback.estimates(from: origins, to: destination) {
            return calibrated(estimates)
        }
        return calibrated(try await straightLineFallback.estimates(from: origins, to: destination))
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        do {
            let route = try await withLocalRouter {
                try await $0.route(from: origin, to: destination)
            }
            debugLog("Walking route: using local OSM graph.")
            return calibrated(route)
        } catch WalkingRoutingError.noRoute {
            // A healthy local graph has established that this pair is not
            // walkable; a fallback estimate must not invent a connection.
            throw WalkingRoutingError.noRoute
        } catch {
            debugLog("Walking route: local OSM graph failed (\(error)); falling back to MapKit.")
        }
        do {
            let route = try await mapKitFallback.route(from: origin, to: destination)
            debugLog("Walking route: using MapKit fallback.")
            return calibrated(route)
        } catch {
            debugLog("Walking route: MapKit fallback failed (\(error)); using straight-line estimate.")
        }
        debugLog("Walking route: using straight-line fallback.")
        return calibrated(try await straightLineFallback.route(from: origin, to: destination))
    }

    private func withLocalRouter<Value: Sendable>(
        _ operation: @Sendable (ValhallaWalkingRouter) async throws -> Value
    ) async throws -> Value {
        guard let dataset = try await datasetManager.activeDataset() else {
            throw WalkingRoutingError.datasetUnavailable
        }
        if routerPool?.version != dataset.version {
            routerPool = RouterPool(version: dataset.version, routers: [], activeCounts: [])
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
            if routerPool?.version == dataset.version,
               routerPool?.activeCounts.indices.contains(index) == true {
                routerPool?.activeCounts[index] -= 1
            }
        }
        return try await operation(router)
    }

    private func calibrated(_ estimates: [OfflineWalkingEstimate]) -> [OfflineWalkingEstimate] {
        estimates.map {
            OfflineWalkingEstimate(
                destinationID: $0.destinationID,
                distanceMeters: $0.distanceMeters,
                duration: WalkingDurationCalibration.adjusted($0.duration),
                source: $0.source
            )
        }
    }

    private func calibrated(_ route: OfflineWalkingRoute) -> OfflineWalkingRoute {
        OfflineWalkingRoute(
            distanceMeters: route.distanceMeters,
            duration: WalkingDurationCalibration.adjusted(route.duration),
            coordinates: route.coordinates,
            source: route.source
        )
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Routing] \(message())")
        #endif
    }
}

/// Bridges the walking abstraction back into the existing route-plan geometry
/// refinement seam. Automobile and bicycle requests remain MapKit-backed.
nonisolated struct LocalFirstRoadRouteProvider: RoadRouteProviding {
    private let walkingRouter: any WalkingRouting
    private let mapKitProvider: MapKitRoadRouteProvider

    init(
        walkingRouter: any WalkingRouting,
        mapKitProvider: MapKitRoadRouteProvider = MapKitRoadRouteProvider()
    ) {
        self.walkingRouter = walkingRouter
        self.mapKitProvider = mapKitProvider
    }

    func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> RoadRoute? {
        guard transport == .walking else {
            return await mapKitProvider.roadRoute(from: origin, to: destination, transport: transport)
        }
        guard let route = try? await walkingRouter.route(from: origin, to: destination) else {
            return nil
        }
        return RoadRoute(
            coordinates: route.coordinates,
            distanceMeters: route.distanceMeters,
            expectedTravelTime: route.duration,
            walkingEvidence: route.source == .straightLineEstimate ? .estimate : .routedPedestrian
        )
    }

    func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }
}

/// Adapts the app's local-first router to MobiliteitKit's transit-search
/// protocol. MobiliteitKit chooses its bounded set of endpoint stop candidates
/// using geographic distance first; every candidate it evaluates here is then
/// measured with the actual pedestrian router.
nonisolated struct LocalFirstWalkingRoutingProvider: WalkingRoutingProvider {
    private let walkingRouter: any WalkingRouting

    init(walkingRouter: any WalkingRouting) {
        self.walkingRouter = walkingRouter
    }

    func estimate(_ request: WalkingRequest) async throws -> WalkingEstimate {
        let source = locationPoint(from: request.source)
        let destination = locationPoint(from: request.destination)
        let estimate = try await walkingRouter.estimates(
            from: source,
            to: [.init(id: destination.id, location: destination)]
        )
        guard let result = estimate.first else { throw WalkingRoutingError.noRoute }
        return WalkingEstimate(
            durationSeconds: max(1, Int(result.duration.rounded())),
            distanceMeters: result.distanceMeters
        )
    }

    func route(_ request: WalkingRequest) async throws -> MobiliteitKit.WalkingRoute {
        let route = try await walkingRouter.route(
            from: locationPoint(from: request.source),
            to: locationPoint(from: request.destination)
        )
        return MobiliteitKit.WalkingRoute(
            durationSeconds: max(1, Int(route.duration.rounded())),
            distanceMeters: route.distanceMeters,
            polyline: route.coordinates.map {
                Coordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            evidence: route.source == .straightLineEstimate ? .estimate : .routedPedestrian
        )
    }

    func routes(
        _ requests: [WalkingRequest],
        maximumConcurrency: Int
    ) async -> [MobiliteitKit.WalkingRoute?] {
        guard !requests.isEmpty else { return [] }
        if let destination = requests.first?.destination,
           requests.allSatisfy({ $0.destination == destination }) {
            let origins = requests.indices.map { index in
                WalkingOrigin(
                    id: String(index),
                    location: locationPoint(from: requests[index].source)
                )
            }
            guard let estimates = try? await walkingRouter.estimates(
                from: origins,
                to: locationPoint(from: destination)
            ) else {
                return Array(repeating: nil, count: requests.count)
            }
            let byID = Dictionary(uniqueKeysWithValues: estimates.map { ($0.destinationID, $0) })
            return requests.indices.map { index in
                guard let estimate = byID[String(index)] else { return nil }
                let request = requests[index]
                return MobiliteitKit.WalkingRoute(
                    durationSeconds: max(1, Int(estimate.duration.rounded())),
                    distanceMeters: estimate.distanceMeters,
                    polyline: [request.source, request.destination],
                    evidence: estimate.source == .straightLineEstimate ? .estimate : .routedPedestrian
                )
            }
        }
        let grouped = Dictionary(grouping: requests.indices) { requests[$0].source }
        let groups = grouped.keys.sorted {
            if $0.latitude != $1.latitude { return $0.latitude < $1.latitude }
            return $0.longitude < $1.longitude
        }.map { source in (source: source, indices: grouped[source] ?? []) }
        let router = walkingRouter
        let limit = min(max(1, maximumConcurrency), groups.count)

        return await withTaskGroup(of: [(Int, MobiliteitKit.WalkingRoute?)].self) { group in
            var nextGroup = 0
            var results = Array<MobiliteitKit.WalkingRoute?>(repeating: nil, count: requests.count)

            func add(_ groupIndex: Int) {
                let item = groups[groupIndex]
                group.addTask {
                    let origin = LocationPoint(
                        latitude: item.source.latitude,
                        longitude: item.source.longitude
                    )
                    let destinations = item.indices.map { index in
                        let request = requests[index]
                        return WalkingDestination(
                            id: String(index),
                            location: LocationPoint(
                                latitude: request.destination.latitude,
                                longitude: request.destination.longitude
                            )
                        )
                    }
                    guard let estimates = try? await router.estimates(from: origin, to: destinations) else {
                        return item.indices.map { ($0, nil) }
                    }
                    let byID = Dictionary(uniqueKeysWithValues: estimates.map { ($0.destinationID, $0) })
                    return item.indices.map { index in
                        guard let estimate = byID[String(index)] else { return (index, nil) }
                        let request = requests[index]
                        return (index, MobiliteitKit.WalkingRoute(
                            durationSeconds: max(1, Int(estimate.duration.rounded())),
                            distanceMeters: estimate.distanceMeters,
                            polyline: [request.source, request.destination],
                            evidence: estimate.source == .straightLineEstimate ? .estimate : .routedPedestrian
                        ))
                    }
                }
            }

            for _ in 0..<limit {
                add(nextGroup)
                nextGroup += 1
            }
            while let values = await group.next() {
                for (index, route) in values { results[index] = route }
                if nextGroup < groups.count {
                    add(nextGroup)
                    nextGroup += 1
                }
            }
            return results
        }
    }

    private func locationPoint(from coordinate: Coordinate) -> LocationPoint {
        LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
