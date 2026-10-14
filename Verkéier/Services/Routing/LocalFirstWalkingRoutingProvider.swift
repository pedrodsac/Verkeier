import Foundation
import MobiliteitKit

/// Bridges the walking abstraction back into the existing route-plan geometry
/// refinement seam. Automobile requests remain MapKit-backed.
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
        // Station rides are presented from the native structured transfer.
        // This legacy geometry-only seam must never flatten one into a walk.
        guard route.segments.isEmpty else { return nil }
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

/// Adapts the app's local pedestrian router to MobiliteitKit's transit-search
/// protocol. MobiliteitKit chooses its bounded set of endpoint stop candidates
/// using geographic distance first; every candidate it evaluates here is then
/// measured with the actual pedestrian router.
nonisolated struct LocalFirstWalkingRoutingProvider: WalkingRoutingProvider {
    private let walkingRouter: any WalkingRouting

    init(walkingRouter: any WalkingRouting) {
        self.walkingRouter = walkingRouter
    }

    func cacheRevision() async -> String? {
        if let router = walkingRouter as? LocalFirstWalkingRouter { return await router.cacheRevision() }
        return nil
    }

    func estimate(_ request: WalkingRequest) async throws -> WalkingEstimate {
        let source = Self.walkingEndpoint(request.source)
        let destination = Self.walkingEndpoint(request.destination)
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
            from: Self.walkingEndpoint(request.source),
            to: Self.walkingEndpoint(request.destination)
        )
        return MobiliteitKit.WalkingRoute(
            durationSeconds: max(1, Int(route.duration.rounded())),
            distanceMeters: route.distanceMeters,
            polyline: route.coordinates.map {
                Coordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            evidence: route.source == .straightLineEstimate ? .estimate : .routedPedestrian,
            segments: route.segments
        )
    }

    func routes(
        _ requests: [WalkingRequest],
        maximumConcurrency: Int
    ) async -> [MobiliteitKit.WalkingRoute?] {
        let routes = await walkingRouter.routes(
            requests.map {
                OfflineWalkingRequest(from: Self.walkingEndpoint($0.source), to: Self.walkingEndpoint($0.destination))
            },
            maximumConcurrency: maximumConcurrency
        )
        return routes.map { route in
            route.map {
                MobiliteitKit.WalkingRoute(
                    durationSeconds: max(1, Int($0.duration.rounded())),
                    distanceMeters: $0.distanceMeters,
                    polyline: $0.coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) },
                    evidence: $0.source == .straightLineEstimate ? .estimate : .routedPedestrian,
                    segments: $0.segments
                )
            }
        }
    }

    /// The single mapping from a package coordinate to a walking endpoint. It is
    /// nameless on purpose: the stored transfer walk table is keyed and built
    /// with exactly this mapping.
    nonisolated static func walkingEndpoint(_ coordinate: Coordinate) -> LocationPoint {
        LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
