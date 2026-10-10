import Foundation
import Testing
@testable import Verkeier

struct MeasuredWalkingRouteCacheTests {
    @Test func cachedPathsAreDirectedAndInvalidateWithGraph() async throws {
        let cache = MeasuredWalkingRouteCache()
        let counter = WalkingCacheCounter()
        let from = LocationPoint(latitude: 49.6, longitude: 6.1)
        let to = LocationPoint(latitude: 49.61, longitude: 6.11)
        func route(_ from: LocationPoint, _ to: LocationPoint, _ revision: String) async throws -> OfflineWalkingRoute {
            try await cache.route(from: from, to: to, revision: revision) {
                await counter.calculate()
            }
        }
        let first = try await route(from, to, "one")
        #expect(try await route(from, to, "one") == first)
        #expect(await counter.calls == 1)
        _ = try await route(to, from, "one")
        _ = try await route(from, to, "two")
        #expect(await counter.calls == 3)
    }

    @Test func cancelledWaiterDoesNotPoisonRetry() async throws {
        let cache = MeasuredWalkingRouteCache()
        let started = WalkingCacheStart()
        let from = LocationPoint(latitude: 49.6, longitude: 6.1)
        let to = LocationPoint(latitude: 49.61, longitude: 6.11)
        let waiting = Task {
            try await cache.route(from: from, to: to, revision: "one") {
                await started.signal()
                try await Task.sleep(for: .seconds(30))
                throw CancellationError()
            }
        }
        await started.wait()
        waiting.cancel()
        do { _ = try await waiting.value; Issue.record("Cancelled path was published") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        let counter = WalkingCacheCounter()
        let retry = try await cache.route(from: from, to: to, revision: "one") { await counter.calculate() }
        #expect(retry.duration == 60)
        #expect(await counter.calls == 1)
    }

    @Test func identicalConcurrentPathsShareCalculation() async throws {
        let cache = MeasuredWalkingRouteCache()
        let counter = WalkingCacheCounter()
        let from = LocationPoint(latitude: 49.6, longitude: 6.1)
        let to = LocationPoint(latitude: 49.61, longitude: 6.11)
        async let a = cache.route(from: from, to: to, revision: "one") { await counter.calculate() }
        async let b = cache.route(from: from, to: to, revision: "one") { await counter.calculate() }
        #expect(try await a == b)
        #expect(await counter.calls == 1)
    }
}
private actor WalkingCacheCounter {
    var calls = 0
    func calculate() async -> OfflineWalkingRoute {
        calls += 1
        await Task.yield()
        return .init(distanceMeters: 100, duration: 60, coordinates: [], source: .localOSM)
    }
}

private actor WalkingCacheStart {
    var signalled = false
    var continuation: CheckedContinuation<Void, Never>?
    func signal() { signalled = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
