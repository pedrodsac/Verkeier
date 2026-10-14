import Foundation
import Testing
@testable import Verkeier

@Suite("Manual route refresh", .serialized)
@MainActor
struct RouteRefreshTests {
    @Test("Unexpected provider errors retain their cause instead of becoming no route found")
    func preservesProviderFailure() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let service = MobiliteitRouteService(databaseURL: databaseURL, walkingRouter: FailingRefreshWalkingRouter())
        await #expect(throws: RefreshFixtureError.failed) {
            try await service.calculateRoute(
                from: .init(latitude: 49.61, longitude: 6.12),
                to: .init(latitude: 49.62, longitude: 6.13),
                time: .leaveNow, filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh, page: .initial
            )
        }
    }

    @Test("A retry waits for a failed calculation and repeated pulls share one forced request")
    func retriesAfterActiveCalculation() async throws {
        let model = makeModel()
        let gate = RefreshRequestGate(failFirst: true)
        let service = RefreshTestService(gate: gate)
        let initial = Task { await model.calculateRoute(using: service, from: nil) }
        try await waitUntil { await gate.count == 1 }
        let firstPull = Task { await model.refreshRoutes(using: service, from: nil) }
        try await waitUntil { model.routeRefreshTask != nil }
        let secondPull = Task { await model.refreshRoutes(using: service, from: nil) }
        // Let the second pull join before the active request completes.
        try await Task.sleep(for: .milliseconds(20))
        #expect(await gate.count == 1)
        await gate.release()
        await initial.value
        await firstPull.value
        await secondPull.value

        #expect(await gate.policies == [.useCache, .forceRefresh])
        #expect(model.routeOptions.map(\.id) == ["recovered"])
        #expect(model.routeErrorMessage == nil)
        #expect(model.routeRefreshTask == nil)
    }

    @Test("Cancellation of the refresh control does not abort the user's retry")
    func refreshOutlivesControlTask() async throws {
        let model = makeModel()
        let gate = RefreshRequestGate()
        let service = RefreshTestService(gate: gate)
        let pull = Task { await model.refreshRoutes(using: service, from: nil) }
        try await waitUntil { await gate.count == 1 }
        pull.cancel()
        await gate.release()
        await pull.value

        #expect(await gate.policies == [.forceRefresh])
        #expect(model.routeOptions.map(\.id) == ["recovered"])
        #expect(model.routeErrorMessage == nil)
        #expect(!model.isCalculatingRoute)
    }

    @Test("Cancelling a calculation does not publish a route unavailable error")
    func cancellationIsNotRouteFailure() async throws {
        let model = makeModel()
        let gate = RefreshRequestGate()
        let service = RefreshTestService(gate: gate)
        let calculation = Task { await model.calculateRoute(using: service, from: nil) }
        try await waitUntil { await gate.count == 1 }
        calculation.cancel()
        await calculation.value
        await gate.release()

        #expect(model.routeErrorMessage == nil)
        #expect(!model.isCalculatingRoute)
    }

    @Test("A queued retry is discarded when the route changes")
    func changedDestinationInvalidatesQueuedRefresh() async throws {
        let model = makeModel()
        let gate = RefreshRequestGate()
        let service = RefreshTestService(gate: gate)
        let initial = Task { await model.calculateRoute(using: service, from: nil) }
        try await waitUntil { await gate.count == 1 }
        let pull = Task { await model.refreshRoutes(using: service, from: nil) }
        try await waitUntil { model.routeRefreshTask != nil }
        model.clearRoute()
        await gate.release()
        await initial.value
        await pull.value

        #expect(await gate.count == 1)
        #expect(model.routeOptions.isEmpty)
        #expect(model.routeRefreshTask == nil)
    }

    @Test("A retry waits for pagination instead of silently returning")
    func waitsForPagination() async throws {
        let model = makeModel()
        let gate = RefreshRequestGate()
        let service = RefreshTestService(gate: gate)
        model.isLoadingLaterRoutes = true
        let pull = Task { await model.refreshRoutes(using: service, from: nil) }
        try await waitUntil { model.routeRefreshTask != nil }
        #expect(await gate.count == 0)
        model.isLoadingLaterRoutes = false
        try await waitUntil { await gate.count == 1 }
        await gate.release()
        await pull.value

        #expect(await gate.policies == [.forceRefresh])
        #expect(model.routeOptions.map(\.id) == ["recovered"])
    }

    private func makeModel() -> RoutePlannerModel {
        let model = RoutePlannerModel()
        model.routeOrigin = RoutePlace(title: "Origin", location: .init(latitude: 49.61, longitude: 6.12), source: .search)
        model.routeDestination = RoutePlace(title: "Destination", location: .init(latitude: 49.62, longitude: 6.13), source: .search)
        return model
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            try #require(ContinuousClock.now < deadline, "Route operation did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor RefreshRequestGate {
    private(set) var policies: [RouteRealtimeRefreshPolicy] = []
    var count: Int { policies.count }
    private var continuation: CheckedContinuation<Void, Never>?
    let failFirst: Bool

    init(failFirst: Bool = false) { self.failFirst = failFirst }

    func request(_ policy: RouteRealtimeRefreshPolicy) async throws {
        policies.append(policy)
        if policies.count == 1 {
            await withCheckedContinuation { continuation = $0 }
            if failFirst { throw RoutingError.noPublicTransportRoute }
        }
        try Task.checkCancellation()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct RefreshTestService: RouteService {
    let gate: RefreshRequestGate

    nonisolated func calculateRoute(
        from: LocationPoint, to: LocationPoint, time: RoutePlanningTime,
        filters: RoutePlannerFilters, realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        try await gate.request(realtimeRefreshPolicy)
        let departure = Date.now.addingTimeInterval(600)
        let arrival = departure.addingTimeInterval(900)
        let option = RouteOption(id: "recovered", plan: RoutePlan(
            id: "recovered", origin: from, destination: to,
            expectedTravelTime: 900, distanceMeters: nil,
            legs: [.init(id: "bus", mode: .bus, transportKind: .transit,
                         origin: from, destination: to, departureTime: departure, arrivalTime: arrival)],
            dataSource: .local
        ), mapOverlay: nil)
        return RouteCalculation(options: [option], selectedOptionID: option.id)
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}

private enum RefreshFixtureError: Error { case failed }

private nonisolated struct FailingRefreshWalkingRouter: WalkingRouting {
    func checkAvailability() async throws { throw RefreshFixtureError.failed }
    func estimates(from: LocationPoint, to: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        throw RefreshFixtureError.failed
    }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        throw RefreshFixtureError.failed
    }
}
