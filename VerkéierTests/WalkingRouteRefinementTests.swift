import Foundation
import Testing
@testable import Verkeier

@Suite("Walking route refinement")
@MainActor
struct WalkingRouteRefinementTests {
    @Test("MapKit route data replaces the walking estimate and keeps boarding fixed")
    func mapKitRouteReplacesWalkingEstimate() async throws {
        let boarding = Date(timeIntervalSince1970: 10_000)
        let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
        let stop = LocationPoint(name: "Stop", latitude: 49.62, longitude: 6.13)
        let destination = LocationPoint(name: "Destination", latitude: 49.63, longitude: 6.14)
        let walkingLeg = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: stop,
            departureTime: boarding.addingTimeInterval(-600),
            arrivalTime: boarding,
            distanceMeters: 750,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(stop)],
            roadRoutingHint: .walking
        )
        let transitLeg = RoutePlan.Leg(
            id: "ride",
            mode: .bus,
            transportKind: .transit,
            origin: stop,
            destination: destination,
            departureTime: boarding,
            arrivalTime: boarding.addingTimeInterval(1_200)
        )
        let option = RouteOption(
            id: "route",
            plan: RoutePlan(
                id: "route",
                origin: origin,
                destination: destination,
                expectedTravelTime: 1_800,
                distanceMeters: 750,
                legs: [walkingLeg, transitLeg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
        let mapKitCoordinates = [
            RouteMapCoordinate(origin),
            RouteMapCoordinate(latitude: 49.615, longitude: 6.125),
            RouteMapCoordinate(stop),
        ]
        let service = MobiliteitRouteService(
            roadRouteProvider: FixedRoadRouteProvider(route: RoadRoute(
                coordinates: mapKitCoordinates,
                distanceMeters: 1_100,
                expectedTravelTime: 900
            ))
        )

        let refined = try #require(await service.refineWalkingRoutes(in: [option]).first)
        let walk = try #require(refined.plan.legs.first)

        #expect(walk.mapCoordinates == mapKitCoordinates)
        #expect(walk.distanceMeters == 1_100)
        #expect(walk.arrivalTime == boarding)
        #expect(walk.departureTime == boarding.addingTimeInterval(-900))
        #expect(refined.plan.expectedTravelTime == 2_100)
        #expect(refined.plan.distanceMeters == 1_100)
    }

    @Test("Walking refinements are emitted as each road route completes")
    func walkingRouteUpdatesAreProgressive() async throws {
        let probe = ProgressiveRoadRouteProbe()
        let fastOrigin = LocationPoint(name: "Fast origin", latitude: 49.61, longitude: 6.12)
        let fastDestination = LocationPoint(name: "Fast destination", latitude: 49.615, longitude: 6.125)
        let slowOrigin = LocationPoint(name: "Slow origin", latitude: 49.62, longitude: 6.13)
        let slowDestination = LocationPoint(name: "Slow destination", latitude: 49.625, longitude: 6.135)
        let options = [
            walkingOption(
                id: "fast",
                origin: fastOrigin,
                destination: fastDestination,
                distance: 500,
                duration: 300
            ),
            walkingOption(
                id: "slow",
                origin: slowOrigin,
                destination: slowDestination,
                distance: 700,
                duration: 420
            ),
        ]
        let service = MobiliteitRouteService(
            roadRouteProvider: DelayedRoadRouteProvider(probe: probe)
        )

        var updates: [RouteOption] = []
        var slowRequestHadCompletedBeforeFirstUpdate = false
        for await option in service.refineWalkingRouteUpdates(in: options) {
            if updates.isEmpty {
                slowRequestHadCompletedBeforeFirstUpdate = await probe.didCompleteSlowRequest
            }
            updates.append(option)
        }

        let first = try #require(updates.first)
        #expect(first.id == "fast")
        #expect(!slowRequestHadCompletedBeforeFirstUpdate)
        #expect(first.plan.legs.first?.distanceMeters == 900)
        #expect(updates.count == 2)
    }

    @Test("Walking refinement starts before progressive route updates finish")
    func refinementStartsWithFirstVisibleUpdate() async throws {
        let probe = RefinementProbe()
        let service = StreamingRefiningRouteService(probe: probe)
        let viewModel = TransitMapViewModel()
        viewModel.routeOrigin = RoutePlace(
            title: "Origin",
            location: service.origin,
            source: .search
        )
        viewModel.routeDestination = RoutePlace(
            title: "Destination",
            location: service.destination,
            source: .search
        )

        let routeTask = Task {
            await viewModel.calculateRoute(using: service, from: nil)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await !probe.didStart, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await probe.didStart)
        #expect(!viewModel.routeOptions.isEmpty)
        #expect(await !probe.didFinishRouteStream)

        routeTask.cancel()
        await routeTask.value
    }

    private func walkingOption(
        id: String,
        origin: LocationPoint,
        destination: LocationPoint,
        distance: Double,
        duration: TimeInterval
    ) -> RouteOption {
        let leg = RoutePlan.Leg(
            id: "\(id)-walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: Date(timeIntervalSince1970: 10_000),
            arrivalTime: Date(timeIntervalSince1970: 10_000 + duration),
            distanceMeters: distance,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            roadRoutingHint: .walking
        )
        return RouteOption(
            id: id,
            plan: RoutePlan(
                id: id,
                origin: origin,
                destination: destination,
                expectedTravelTime: duration,
                distanceMeters: distance,
                legs: [leg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
    }
}

private struct FixedRoadRouteProvider: RoadRouteProviding {
    let route: RoadRoute

    nonisolated func roadRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> RoadRoute? {
        route
    }

    nonisolated func roadRouteCoordinates(
        from _: LocationPoint,
        to _: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        route.coordinates
    }
}

private actor ProgressiveRoadRouteProbe {
    private(set) var didCompleteSlowRequest = false

    func markCompleted(isSlow: Bool) {
        if isSlow {
            didCompleteSlowRequest = true
        }
    }
}

private struct DelayedRoadRouteProvider: RoadRouteProviding {
    let probe: ProgressiveRoadRouteProbe

    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> RoadRoute? {
        let isSlow = origin.latitude > 49.615
        try? await Task.sleep(for: isSlow ? .milliseconds(250) : .milliseconds(20))
        await probe.markCompleted(isSlow: isSlow)
        return RoadRoute(
            coordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            distanceMeters: isSlow ? 1_100 : 900,
            expectedTravelTime: isSlow ? 600 : 480
        )
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }
}

private actor RefinementProbe {
    var didStart = false
    var didFinishRouteStream = false

    func markStarted() {
        didStart = true
    }

    func markStreamFinished() {
        didFinishRouteStream = true
    }
}

private struct StreamingRefiningRouteService: RouteService, WalkingRouteRefining {
    let probe: RefinementProbe
    let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
    let destination = LocationPoint(name: "Destination", latitude: 49.62, longitude: 6.13)

    nonisolated func calculateRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) async throws -> RouteCalculation {
        calculation
    }

    nonisolated func routeCalculationUpdates(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(calculation)
                do {
                    try await Task.sleep(for: .seconds(5))
                    await probe.markStreamFinished()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] {
        await probe.markStarted()
        return options
    }

    @MainActor func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}

    private nonisolated var calculation: RouteCalculation {
        let departure = Date(timeIntervalSince1970: 10_000)
        let leg = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: departure,
            arrivalTime: departure.addingTimeInterval(600),
            distanceMeters: 750,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            roadRoutingHint: .walking
        )
        let option = RouteOption(
            id: "walk-route",
            plan: RoutePlan(
                id: "walk-route",
                origin: origin,
                destination: destination,
                expectedTravelTime: 600,
                distanceMeters: 750,
                legs: [leg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
        return RouteCalculation(options: [option], selectedOptionID: option.id)
    }
}
