import Foundation
import Testing
@testable import Verkeier

@Suite("Walking route visibility")
@MainActor
struct RouteWalkingVisibilityTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Walking alone is shown when it arrives earlier and takes less time than every ride")
    func fasterWalkReplacesTransit() async {
        let walk = option("walk", mode: .walking, duration: 600)
        let bus = option("bus", duration: 1_200)
        let tram = option("tram", mode: .tram, duration: 900)
        let model = await calculate([bus, tram, walk], recommended: bus.id)
        #expect(model.routeOptions.map(\.id) == [walk.id])
        #expect(model.selectedRouteOptionID == walk.id)
        #expect(model.unfilteredRouteOptions.map(\.id) == [bus.id, tram.id, walk.id])
    }

    @Test("An earlier walk stays alongside a later, shorter bus journey")
    func earlierArrivalWithLongerDuration() async {
        let walk = option("walk", mode: .walking, duration: 1_200)
        let bus = option("bus", departure: 900, duration: 600)
        let model = await calculate([bus, walk], recommended: bus.id)
        #expect(model.routeOptions.map(\.id) == [bus.id, walk.id])
    }

    @Test("Walking is hidden when any bus or tram arrives as soon or sooner", arguments: [1_199.0, 1_200.0, 1_500.0])
    func walkingMustBeatEarliestArrival(walkingDuration: TimeInterval) async {
        let bus = option("bus", duration: 1_800)
        let tram = option("tram", mode: .tram, duration: 1_199)
        let walk = option("walk", mode: .walking, duration: walkingDuration)
        let model = await calculate([bus, tram, walk], recommended: walk.id)
        #expect(model.routeOptions.map(\.id) == [bus.id, tram.id])
        #expect(model.selectedRouteOptionID != walk.id)
    }

    @Test("An equal duration keeps transit even when walking arrives first")
    func equalDurationKeepsTransit() async {
        let walk = option("walk", mode: .walking, duration: 900)
        let bus = option("bus", departure: 300, duration: 900)
        let model = await calculate([bus, walk], recommended: walk.id)
        #expect(model.routeOptions.map(\.id) == [bus.id, walk.id])
    }

    @Test("The comparison uses realtime arrival and complete door-to-door duration")
    func realtimeChangesVisibility() async {
        let walk = option("walk", mode: .walking, duration: 900)
        let delayedBus = option("bus", duration: 600, realtimeArrival: 1_200)
        let model = await calculate([delayedBus, walk], recommended: delayedBus.id)
        #expect(model.routeOptions.map(\.id) == [walk.id])
    }

    @Test("Transit duration includes access walking, waiting, and egress walking")
    func comparesDoorToDoorDuration() async {
        let walk = option("walk", mode: .walking, duration: 900)
        let bus = option("bus", departure: 300, duration: 300)
        let access = option("access", mode: .walking, duration: 120).plan.legs[0]
        let egress = option("egress", mode: .walking, departure: 600, duration: 600).plan.legs[0]
        let doorToDoor = bus.replacingLegs([access, bus.plan.legs[0], egress], expectedTravelTime: 1_200)
        let model = await calculate([doorToDoor, walk], recommended: bus.id)
        #expect(model.routeOptions.map(\.id) == [walk.id])
    }

    @Test("Walking remains available when there is no transit route")
    func walkingFallback() async {
        let walk = option("walk", mode: .walking, duration: 1_800)
        let model = await calculate([walk], recommended: walk.id)
        #expect(model.routeOptions.map(\.id) == [walk.id])
    }

    @Test("An unknown transit arrival cannot prove that walking arrives earlier")
    func unknownArrivalKeepsTransit() {
        let walk = option("walk", mode: .walking, duration: 600)
        let knownBus = option("bus", duration: 900)
        let leg = RoutePlan.Leg(id: "unknown", mode: .bus, transportKind: .transit,
            origin: knownBus.plan.origin, destination: knownBus.plan.destination)
        let bus = knownBus.replacingLegs([leg])
        let visible = RouteOptionVisibility.visibleOptions(primary: [bus, walk], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [bus.id])
    }

    @Test("A manual bus selection falls back to walking when only walking qualifies")
    func hiddenManualSelectionFallsBack() async {
        let bus = option("bus", duration: 1_200)
        let model = await calculate([bus], recommended: bus.id)
        model.selectRouteOption(id: bus.id)
        let walk = option("walk", mode: .walking, duration: 600)
        await model.calculateRoute(using: WalkingVisibilityFixture(options: [bus, walk], recommended: bus.id), from: nil)
        #expect(model.routeOptions.map(\.id) == [walk.id])
        #expect(model.selectedRouteOptionID == walk.id)
    }

    @Test("A slower walking refinement restores hidden transit and bike alternatives")
    func refinementRestoresAlternatives() async throws {
        let bus = option("bus", duration: 1_200)
        let walk = option("walk", mode: .walking, duration: 600)
        let bike = option("bike", mode: .bicycle, duration: 900)
        let (updates, continuation) = AsyncStream<WalkingRefinementEvent>.makeStream()
        let service = WalkingVisibilityFixture(options: [bus, walk], supplemental: [bike],
            recommended: bus.id, refinements: updates)
        let model = configuredModel()
        await model.calculateRoute(using: service, from: nil)
        #expect(model.routeOptions.map(\.id) == [walk.id])
        #expect(model.supplementalRouteOptions.isEmpty)

        continuation.yield(.option(option("walk", mode: .walking, duration: 1_800)))
        continuation.finish()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.routeOptions.first?.id != bus.id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.routeOptions.map(\.id) == [bus.id])
        #expect(model.supplementalRouteOptions.map(\.id) == [bike.id])
        #expect(model.selectedRouteOptionID != walk.id)
    }

    @Test("Paging applies the same walking visibility rule")
    func pagedResultsUseVisibility() async {
        let bus = option("bus", duration: 1_200)
        let model = await calculate([bus], recommended: bus.id)
        let walk = option("walk", mode: .walking, duration: 600)
        await model.loadLaterRoutes(using: WalkingVisibilityFixture(options: [bus, walk], recommended: bus.id), from: nil)
        #expect(model.routeOptions.map(\.id) == [walk.id])
        #expect(model.selectedRouteOptionID == walk.id)
    }

    private func calculate(_ options: [RouteOption], recommended: String) async -> TransitMapViewModel {
        let model = configuredModel()
        await model.calculateRoute(using: WalkingVisibilityFixture(options: options, recommended: recommended), from: nil)
        return model
    }

    private func configuredModel() -> TransitMapViewModel {
        let model = TransitMapViewModel(now: { anchor })
        model.routeOrigin = RoutePlace(title: "Origin", location: .init(latitude: 49.6, longitude: 6.1), source: .search)
        model.routeDestination = RoutePlace(title: "Destination", location: .init(latitude: 49.61, longitude: 6.1), source: .search)
        model.routePlanningTime = .departAt(anchor)
        return model
    }

    private func option(_ id: String, mode: TransportMode = .bus, departure: TimeInterval = 0,
        duration: TimeInterval, realtimeArrival: TimeInterval? = nil
    ) -> RouteOption {
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(latitude: 49.61, longitude: 6.1)
        let kind: RouteLegTransportKind = mode == .walking ? .walking : mode == .bicycle ? .bikeShare : .transit
        let leg = RoutePlan.Leg(id: id, mode: mode, transportKind: kind,
            origin: origin, destination: destination,
            departureTime: anchor.addingTimeInterval(departure),
            arrivalTime: anchor.addingTimeInterval(departure + duration),
            realtimeArrivalTime: realtimeArrival.map { anchor.addingTimeInterval($0) })
        return RouteOption(id: id, plan: .init(id: id, origin: origin, destination: destination,
            expectedTravelTime: duration, distanceMeters: 0, legs: [leg], dataSource: .local), mapOverlay: nil)
    }
}

private struct WalkingVisibilityFixture: RouteService, WalkingRouteRefining {
    let options: [RouteOption]
    var supplemental: [RouteOption] = []
    let recommended: String
    var refinements: AsyncStream<WalkingRefinementEvent>? = nil

    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint,
        time: RoutePlanningTime, filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        var result = RouteCalculation(options: options, supplementalOptions: supplemental, selectedOptionID: recommended)
        result.isAuthoritativeSnapshot = true
        result.canLoadEarlier = true
        result.canLoadLater = true
        return result
    }

    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] { options }

    nonisolated func refinementEvents(in options: [RouteOption], context: RouteValidationContext?) -> AsyncStream<WalkingRefinementEvent> {
        if options.contains(where: \.isWalkingOnly), let refinements { return refinements }
        return AsyncStream { $0.finish() }
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}
