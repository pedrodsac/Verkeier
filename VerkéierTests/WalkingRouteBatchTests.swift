import Foundation
import Testing
@testable import Verkeier

struct WalkingRouteBatchTests {
    @Test func batchPreservesEveryRequestAndFailureWithBoundedConcurrency() async {
        let router = BatchWalkingFixture(failures: [3, 7])
        let requests = (0..<20).map(Self.request)
        let routes = await router.routes(requests, maximumConcurrency: 2)
        #expect(routes.count == requests.count)
        for index in requests.indices {
            #expect(routes[index]?.duration == ([3, 7].contains(index) ? nil : Double(index + 1)))
        }
        #expect(await router.calls == 20)
        #expect(await router.maximumActive == 2)
    }

    @Test func cancellationStopsQueuedWalkingWork() async {
        let router = BatchWalkingFixture(suspend: true)
        let task = Task { await router.routes((0..<20).map(Self.request), maximumConcurrency: 2) }
        await router.waitUntilStarted()
        task.cancel()
        let routes = await task.value
        #expect(routes.count == 20)
        #expect(routes.allSatisfy { $0 == nil })
        #expect(await router.calls <= 2)
    }

    private static func request(_ index: Int) -> OfflineWalkingRequest {
        .init(from: .init(latitude: 49.6, longitude: 6),
              to: .init(latitude: 49.6, longitude: Double(index)))
    }
}

private actor BatchWalkingFixture: WalkingRouting {
    let failures: Set<Int>
    let suspend: Bool
    var calls = 0
    var active = 0
    var maximumActive = 0
    var started: CheckedContinuation<Void, Never>?

    init(failures: Set<Int> = [], suspend: Bool = false) {
        self.failures = failures; self.suspend = suspend
    }

    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        calls += 1; active += 1; maximumActive = max(active, maximumActive)
        started?.resume(); started = nil
        defer { active -= 1 }
        let index = Int(to.longitude)
        try await Task.sleep(for: suspend ? .seconds(30) : .milliseconds(index.isMultiple(of: 2) ? 4 : 1))
        if failures.contains(index) { throw WalkingRoutingError.noRoute }
        return .init(distanceMeters: 100, duration: Double(index + 1), coordinates: [], source: .localOSM)
    }

    func estimates(from: LocationPoint, to: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] { [] }
}
