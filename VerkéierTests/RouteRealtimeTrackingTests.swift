import Foundation
import Testing
@testable import Verkeier

@Suite("Calculated route live tracking")
@MainActor
struct RouteRealtimeTrackingTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func allAlternativesUpdateAndManualSelectionSurvives() async throws {
        let model = configuredModel()
        let initial = (0..<10).map { option("route-\($0)", offset: Double($0 * 300)) }
        let live = (0..<10).map { option("route-\($0)", offset: Double($0 * 300), live: true) }
        let service = TrackingRouteService(initial: initial, updated: live)
        await model.calculateRoute(using: service, from: nil)
        _ = model.selectRouteOption(id: "route-4")
        let request = try #require(model.routeRealtimeRequest)
        await model.refreshRouteRealtime(using: service, request: request)
        #expect(model.unfilteredRouteOptions.count == 10)
        #expect(model.unfilteredRouteOptions.flatMap(\.transitLegs).allSatisfy { $0.liveStatus == .live })
        #expect(model.selectedRouteOptionID == "route-4")
        #expect(!model.isCalculatingRoute)
    }

    @Test func cancelledChoiceIsRemovedAndSelectionFallsBack() async throws {
        let model = configuredModel()
        let first = option("first"), replacement = option("replacement", offset: 600)
        let backup = option("backup", offset: 1_200)
        let service = TrackingRouteService(initial: [first, replacement, backup],
            updated: [option("replacement", offset: 600, live: true), backup], invalidated: ["first"])
        await model.calculateRoute(using: service, from: nil)
        let request = try #require(model.routeRealtimeRequest)
        await model.refreshRouteRealtime(using: service, request: request)
        #expect(model.routeOptions.map(\.id) == ["replacement", "backup"])
        #expect(model.selectedRouteOptionID == "replacement")
        #expect(model.invalidatedRouteOptionIDs.contains("first"))
    }

    @Test func endpointChangeRejectsAnInFlightUpdate() async throws {
        let model = configuredModel()
        let gate = TrackingGate()
        let service = TrackingRouteService(initial: [option("old")], updated: [option("old", live: true)], gate: gate)
        await model.calculateRoute(using: service, from: nil)
        let request = try #require(model.routeRealtimeRequest)
        let refresh = Task { await model.refreshRouteRealtime(using: service, request: request) }
        await gate.waitUntilEntered()
        model.clearRoute()
        await gate.release()
        await refresh.value
        #expect(model.routeOptions.isEmpty)
        #expect(model.routeRealtimeRequest == nil)
    }

    @Test func visibleSessionRefreshesRepeatedlyAndCancellationStopsIt() async throws {
        let model = configuredModel()
        let recorder = TrackingRecorder()
        let service = TrackingRouteService(initial: [option("route")], updated: [option("route", live: true)], recorder: recorder)
        await model.calculateRoute(using: service, from: nil)
        let request = try #require(model.routeRealtimeRequest)
        let task = Task { await model.trackRouteRealtime(using: service, request: request, interval: .milliseconds(5)) }
        await recorder.waitForTwoRefreshes()
        task.cancel()
        await task.value
        let count = await recorder.count
        try await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.count == count)
        #expect(count >= 2)
        let policies = await recorder.policies
        #expect(policies.first == .useCache)
        #expect(policies.dropFirst().allSatisfy { $0 == .forceRefresh })
    }

    @Test func pagingTemporarilyDisablesTrackingAndKeepsAllLoadedOptions() async throws {
        let model = configuredModel()
        let all = [option("first"), option("later", offset: 1_200)]
        let service = TrackingRouteService(initial: all, updated: all)
        await model.calculateRoute(using: service, from: nil)
        #expect(model.routeRealtimeRequest != nil)
        model.isLoadingLaterRoutes = true
        #expect(model.routeRealtimeRequest == nil)
        model.isLoadingLaterRoutes = false
        let request = try #require(model.routeRealtimeRequest)
        await model.refreshRouteRealtime(using: service, request: request)
        #expect(model.unfilteredRouteOptions.map(\.id) == ["first", "later"])
    }

    private func configuredModel() -> TransitMapViewModel {
        let model = TransitMapViewModel(now: { anchor })
        model.routeOrigin = .init(title: "Origin", location: .init(latitude: 49.6, longitude: 6.1), source: .search)
        model.routeDestination = .init(title: "Destination", location: .init(latitude: 49.7, longitude: 6.2), source: .search)
        model.routePlanningTime = .departAt(anchor)
        return model
    }

    private func option(_ id: String, offset: TimeInterval = 0, live: Bool = false) -> RouteOption {
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(latitude: 49.7, longitude: 6.2)
        let departure = anchor.addingTimeInterval(300 + offset)
        let leg = RoutePlan.Leg(id: id, mode: .bus, transportKind: .transit, routeName: id, origin: origin, destination: destination,
            departureTime: departure, arrivalTime: departure.addingTimeInterval(600), liveStatus: live ? .live : .scheduled)
        return .init(id: id, plan: .init(id: id, origin: origin, destination: destination,
            expectedTravelTime: 600, distanceMeters: 0, legs: [leg], dataSource: .local), mapOverlay: nil)
    }
}

private struct TrackingRouteService: RouteService, RouteRealtimeRefreshing {
    let initial: [RouteOption]
    let updated: [RouteOption]
    var invalidated: Set<String> = []
    var gate: TrackingGate? = nil
    var recorder: TrackingRecorder? = nil
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint, time: RoutePlanningTime,
        filters: RoutePlannerFilters, realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        .init(options: initial, selectedOptionID: initial.first?.id)
    }
    nonisolated func refreshRouteRealtime(from: LocationPoint, to: LocationPoint,
        refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> RouteCalculation? {
        await gate?.enter()
        await recorder?.record(refreshPolicy)
        var calculation = RouteCalculation(options: updated, selectedOptionID: updated.first?.id)
        calculation.isAuthoritativeSnapshot = true
        calculation.invalidatedOptionIDs = invalidated
        return calculation
    }
    func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}

private actor TrackingGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        enteredWaiter?.resume(); enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private actor TrackingRecorder {
    var count = 0
    var policies: [RouteRealtimeRefreshPolicy] = []
    private var waiter: CheckedContinuation<Void, Never>?
    func record(_ policy: RouteRealtimeRefreshPolicy) {
        count += 1
        policies.append(policy)
        if count >= 2 { waiter?.resume(); waiter = nil }
    }
    func waitForTwoRefreshes() async {
        if count >= 2 { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
