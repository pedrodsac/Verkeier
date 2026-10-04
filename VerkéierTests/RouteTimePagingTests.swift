import CoreLocation
import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Route time controls", .serialized)
@MainActor
struct RouteTimePagingTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pagingKeepsSelectionAndAddsFiveRoutesWithoutDuplicates() async {
        let first = option("first", departure: 300)
        let added = (1...5).map { option("page-\($0)", departure: Double($0 * 900)) }
        let service = TimePageFixture(initial: [first], paged: [first] + added)
        let model = configuredModel()
        await model.calculateRoute(using: service, from: nil)
        await model.loadLaterRoutes(using: service, from: nil)
        #expect(model.routeOptions.count == 6)
        #expect(model.selectedRouteOptionID == first.id)
        #expect(model.routeBrowsingWindow?.axis == .departure)
        #expect(model.canLoadLaterRoutes)
        await model.loadLaterRoutes(using: service, from: nil)
        #expect(model.routeOptions.count == 6)
        #expect(model.routeStatusMessage == "No later routes were found.")
    }

    @Test func emptySnapshotKeepsExistingRoutesAndDisablesOnlyExhaustedDirection() async {
        let first = option("first", departure: 300)
        let model = configuredModel()
        let service = TimePageFixture(initial: [first], paged: [first], hasLater: false)
        await model.calculateRoute(using: service, from: nil)
        await model.loadLaterRoutes(using: service, from: nil)
        #expect(model.routeOptions.map(\.id) == [first.id])
        #expect(model.selectedRouteOptionID == first.id)
        #expect(!model.canLoadLaterRoutes)
        #expect(model.canLoadEarlierRoutes)
        #expect(model.routeStatusMessage == "No later routes were found.")
    }

    @Test func stalledPageTimesOutPreservesResultsAndAllowsRetry() async {
        let first = option("first", departure: 300)
        let model = configuredModel(timeout: .milliseconds(30))
        let stalled = TimePageFixture(initial: [first], paged: [], stallPages: true)
        await model.calculateRoute(using: stalled, from: nil)
        let started = ContinuousClock.now
        await model.loadLaterRoutes(using: stalled, from: nil)
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(model.routeOptions.map(\.id) == [first.id])
        #expect(model.selectedRouteOptionID == first.id)
        #expect(!model.isLoadingLaterRoutes)
        #expect(model.canLoadLaterRoutes)
        #expect(model.routeStatusMessage == "Later routes could not be loaded. Try again.")
        let next = option("next", departure: 1200)
        await model.loadLaterRoutes(using: TimePageFixture(initial: [first], paged: [first, next]), from: nil)
        #expect(model.routeOptions.map(\.id) == [first.id, next.id])
    }

    @Test func endpointChangeRejectsLatePageAndResetsBrowsingWindow() async {
        let first = option("first", departure: 300)
        let model = configuredModel()
        let gate = TimePageGate()
        let service = TimePageFixture(initial: [first], paged: [first, option("old-page", departure: 1200)], gate: gate)
        await model.calculateRoute(using: service, from: nil)
        let task = Task { await model.loadEarlierRoutes(using: service, from: nil) }
        while !(await gate.isWaiting) { await Task.yield() }
        model.setRoutePlanningTime(.arriveBy(anchor.addingTimeInterval(7200)))
        await gate.release()
        await task.value
        #expect(model.routeOptions.isEmpty)
        #expect(model.routeBrowsingWindow == nil)
        #expect(!model.isLoadingEarlierRoutes)
    }

    @Test func filterChangeInvalidatesPendingPage() async {
        let first = option("first", departure: 300)
        let model = configuredModel()
        let gate = TimePageGate()
        let service = TimePageFixture(initial: [first], paged: [first], gate: gate)
        await model.calculateRoute(using: service, from: nil)
        let task = Task { await model.loadLaterRoutes(using: service, from: nil) }
        while !(await gate.isWaiting) { await Task.yield() }
        model.updateRouteFilters(.init(modePreference: .train))
        await gate.release()
        await task.value
        #expect(model.routeOptions.isEmpty)
        #expect(!model.isLoadingLaterRoutes)
    }

    @Test func gpsMovementDoesNotChangePagingOriginOrChosenTime() async {
        let recorder = TimePageRecorder()
        let first = option("first", departure: 300)
        let model = configuredModel()
        model.routeOrigin = nil
        let service = TimePageFixture(initial: [first], paged: [first], recorder: recorder)
        await model.calculateRoute(using: service, from: .init(latitude: 49.6, longitude: 6.1))
        await model.loadLaterRoutes(using: service, from: .init(latitude: 49.601, longitude: 6.101))
        let origins = await recorder.origins
        #expect(origins.count == 2)
        #expect(origins[0] == origins[1])
        #expect(await recorder.times == [.departAt(anchor), .departAt(anchor)])
        #expect(model.routePlanningTime == .departAt(anchor))
    }

    @Test func arrivalPresentationOrdersByDestinationTime() {
        let late = option("late", departure: 300, duration: 3600)
        let early = option("early", departure: 1200, duration: 600)
        var presentation = RoutePresentationModel(selectedStop: nil, origin: nil, destination: nil,
            currentLocation: nil, favouritePlaces: [], nearbyPlaces: [], recentPlaces: [],
            commutePresets: [], filters: .init(), planningTime: .arriveBy(anchor.addingTimeInterval(7200)),
            routeOptions: [late, early], alerts: [], selectedRouteOptionID: nil,
            loadingPhase: .idle, errorMessage: nil, statusMessage: nil)
        presentation.browsingWindow = .init(axis: .arrival,
            range: .init(start: anchor, duration: 7200))
        #expect(presentation.chronologicallyOrderedRouteOptions.map(\.id) == [early.id, late.id])
        #expect(presentation.browsedTimeRange != nil)
    }

    @Test func refinementUsesJourneyDeadlineInsteadOfOriginalDeadline() async {
        var route = option("later-arrival", departure: 300, duration: 3600)
        route.validationContext = .init(anchor: anchor.addingTimeInterval(7200), arriveBy: true,
                                        minimumTransferSeconds: 120)
        let original = RouteValidationContext(anchor: anchor.addingTimeInterval(1800), arriveBy: true,
                                               minimumTransferSeconds: 120)
        let replacement = route.replacingLegs(route.plan.legs)
        #expect(replacement.validationContext == route.validationContext)
        let restored = try? JSONDecoder().decode(RouteOption.self, from: JSONEncoder().encode(replacement))
        #expect(restored?.validationContext == route.validationContext)
        let service = TimeRefinementFixture(option: route)
        var published: [String] = []
        for await event in service.refinementEvents(in: [route], context: original) {
            if case let .option(option) = event { published.append(option.id) }
            if case .invalidated = event { Issue.record("Used the original deadline for a later page") }
        }
        #expect(published == [route.id])
    }

    private func configuredModel(timeout: Duration = .seconds(15)) -> TransitMapViewModel {
        let model = TransitMapViewModel(now: { anchor }, routeCalculationTimeout: timeout)
        model.routeOrigin = RoutePlace(title: "Origin", location: .init(latitude: 49.6, longitude: 6.1), source: .search)
        model.routeDestination = RoutePlace(title: "Destination", location: .init(latitude: 49.61, longitude: 6.1), source: .search)
        model.routePlanningTime = .departAt(anchor)
        return model
    }

    private func option(_ id: String, departure: Double, duration: Double = 600) -> RouteOption {
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(latitude: 49.61, longitude: 6.1)
        return .init(id: id, plan: .init(id: id, origin: origin, destination: destination,
            expectedTravelTime: duration, distanceMeters: nil,
            legs: [.init(id: id, mode: .bus, transportKind: .transit, origin: origin, destination: destination,
                departureTime: anchor.addingTimeInterval(departure),
                arrivalTime: anchor.addingTimeInterval(departure + duration))], dataSource: .local), mapOverlay: nil)
    }
}

private struct TimePageFixture: RouteService {
    let initial: [RouteOption]
    let paged: [RouteOption]
    var hasLater = true
    var stallPages = false
    var gate: TimePageGate?
    var recorder: TimePageRecorder?

    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint, time: RoutePlanningTime,
        filters: RoutePlannerFilters, realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        await recorder?.record(origin: from, time: time)
        if page != .initial {
            if stallPages { try await Task.sleep(for: .seconds(5)) }
            await gate?.wait()
        }
        let options = page == .initial ? initial : paged
        var result = RouteCalculation(options: options, selectedOptionID: options.last?.id)
        result.isAuthoritativeSnapshot = true
        result.canLoadEarlier = true
        result.canLoadLater = page == .initial ? true : hasLater
        if let first = options.first?.departureTime, let last = options.last?.departureTime {
            result.browsingWindow = .init(axis: .departure, range: .init(start: first, end: last))
        }
        return result
    }
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}

private actor TimePageGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

private actor TimePageRecorder {
    var origins: [LocationPoint] = []
    var times: [RoutePlanningTime] = []
    func record(origin: LocationPoint, time: RoutePlanningTime) { origins.append(origin); times.append(time) }
}

private struct TimeRefinementFixture: WalkingRouteRefining {
    let option: RouteOption
    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] { [option] }
}
