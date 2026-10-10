import Foundation
import Testing
@testable import Verkeier

@Suite("Route detail live refresh")
@MainActor
struct RouteRealtimeTrackingTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func onlySelectedRouteUpdatesAndManualSelectionSurvives() async throws {
        let model = configuredModel()
        let initial = (0..<10).map { option("route-\($0)", offset: Double($0 * 300)) }
        let live = (0..<10).map { option("route-\($0)", offset: Double($0 * 300), live: true) }
        let service = TrackingRouteService(initial: initial, updated: live)
        await model.calculateRoute(using: service, from: nil)
        _ = model.selectRouteOption(id: "route-4")
        let request = try #require(model.routeRealtimeRequest)
        await model.refreshRouteRealtime(using: service, request: request)
        #expect(model.unfilteredRouteOptions.count == 10)
        #expect(model.unfilteredRouteOptions.first { $0.id == "route-4" }?.transitLegs.first?.liveStatus == .live)
        #expect(model.unfilteredRouteOptions.filter { $0.id != "route-4" } == initial.filter { $0.id != "route-4" })
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

    @Test func manualRefreshMakesOneForcedRequestForTheSelectedRoute() async throws {
        let model = configuredModel()
        let recorder = TrackingRecorder()
        let service = TrackingRouteService(initial: [option("first"), option("second", offset: 600)],
            updated: [option("second", offset: 600, live: true)], recorder: recorder)
        await model.calculateRoute(using: service, from: nil)
        #expect(await recorder.policies.isEmpty)
        _ = model.selectRouteOption(id: "second")
        await model.refreshSelectedRouteRealtime(using: service)
        #expect(await recorder.policies == [.forceRefresh])
        #expect(await recorder.optionIDs == ["second"])
        #expect(model.selectedRouteOptionID == "second")
    }

    @Test func selectionChangeRejectsAnInFlightUpdate() async throws {
        let model = configuredModel()
        let initial = [option("first"), option("second", offset: 600)]
        let gate = TrackingGate()
        let service = TrackingRouteService(initial: initial, updated: [option("first", live: true)], gate: gate)
        await model.calculateRoute(using: service, from: nil)
        let refresh = Task { await model.refreshSelectedRouteRealtime(using: service) }
        await gate.waitUntilEntered()
        _ = model.selectRouteOption(id: "second")
        await gate.release()
        await refresh.value
        #expect(model.unfilteredRouteOptions == initial)
        #expect(model.selectedRouteOptionID == "second")
    }

    @Test func failedRefreshKeepsExistingRouteAndReportsTheFailure() async throws {
        let model = configuredModel()
        let initial = [option("route")]
        let service = TrackingRouteService(initial: initial, updated: [], fail: true)
        await model.calculateRoute(using: service, from: nil)
        await model.refreshSelectedRouteRealtime(using: service)
        #expect(model.unfilteredRouteOptions == initial)
        #expect(model.selectedRouteOptionID == "route")
        #expect(model.routeStatusMessage?.contains("could not be refreshed") == true)
    }

    @Test func pagingDisablesDetailRefreshAndKeepsAllLoadedOptions() async throws {
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
    var fail = false
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint, time: RoutePlanningTime,
        filters: RoutePlannerFilters, realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        .init(options: initial, selectedOptionID: initial.first?.id)
    }
    nonisolated func refreshRouteRealtime(optionID: String, from: LocationPoint, to: LocationPoint,
        refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> RouteCalculation? {
        await gate?.enter()
        await recorder?.record(optionID, refreshPolicy)
        if fail { throw URLError(.notConnectedToInternet) }
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
    var policies: [RouteRealtimeRefreshPolicy] = []
    var optionIDs: [String] = []
    func record(_ optionID: String, _ policy: RouteRealtimeRefreshPolicy) {
        optionIDs.append(optionID)
        policies.append(policy)
    }
}
