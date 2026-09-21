import Foundation
import MobiliteitKit

/// Chooses the active immutable OSM graph first, then MapKit, then a clearly
/// identified straight-line approximation. A replacement graph is picked up on
/// the next request without ever modifying an engine's open tile archive.
actor LocalFirstWalkingRouter: WalkingRouting {
    private let datasetManager: RoutingDatasetManager
    private let mapKitFallback: any WalkingRouting
    private let straightLineFallback: any WalkingRouting
    private var cachedRouter: (version: String, router: ValhallaWalkingRouter)?

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
            let router = try await localRouter()
            do {
                let estimates = try await router.estimates(from: origin, to: destinations)
                debugLog("Walking estimates: using local OSM graph for \(destinations.count) destination(s).")
                return calibrated(estimates)
            } catch {
                debugLog("Walking estimates: local OSM graph failed (\(error)); falling back to MapKit.")
            }
        } catch {
            debugLog("Walking estimates: local OSM graph unavailable (\(error)); falling back to MapKit.")
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

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        do {
            let router = try await localRouter()
            do {
                let route = try await router.route(from: origin, to: destination)
                debugLog("Walking route: using local OSM graph.")
                return calibrated(route)
            } catch {
                debugLog("Walking route: local OSM graph failed (\(error)); falling back to MapKit.")
            }
        } catch {
            debugLog("Walking route: local OSM graph unavailable (\(error)); falling back to MapKit.")
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

    private func localRouter() async throws -> ValhallaWalkingRouter {
        guard let dataset = try await datasetManager.activeDataset() else {
            throw WalkingRoutingError.datasetUnavailable
        }
        if let cachedRouter, cachedRouter.version == dataset.version {
            return cachedRouter.router
        }
        let router = try ValhallaWalkingRouter(
            tileArchiveURL: dataset.tileArchiveURL,
            datasetVersion: dataset.version
        )
        cachedRouter = (dataset.version, router)
        return router
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
            expectedTravelTime: route.duration
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
            }
        )
    }

    private func locationPoint(from coordinate: Coordinate) -> LocationPoint {
        LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
