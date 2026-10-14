import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Transfer walk table builder", .serialized)
struct TransferWalkTableBuilderTests {
    static let dataset = RoutingDataset(
        manifest: TransferWalkTableCodecTests.manifest(version: "v1", sha: "aaa"),
        tileArchiveURL: URL(fileURLWithPath: "/dev/null"), storageRevision: "rev-1")

    /// A line of stops; every ordered pair of neighbours within `span` is a request.
    static func requests(_ range: Range<Int>, span: Int = 3) -> [WalkingRequest] {
        var result: [WalkingRequest] = []
        for from in range { for to in range where from != to && abs(from - to) <= span { result.append(WalkingRequest(source: stop(from), destination: stop(to))) } }
        return result
    }

    static func stop(_ index: Int) -> Coordinate {
        .init(latitude: 49.5 + Double(index) * 0.001, longitude: 6.1 + Double(index % 7) * 0.0007)
    }

    private func build(_ computer: FakeComputer, _ requests: [WalkingRequest], reusing: TransferWalkTable? = nil,
                       timetable: String? = "t1", progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> TransferWalkBuildResult {
        try await TransferWalkTableBuilder(computer: computer).build(
            requests: requests, dataset: Self.dataset, reusing: reusing, timetableIdentity: timetable, progress: progress)
    }

    @Test("A full build computes each distinct pair once, sorted, with nameless points")
    func fullBuild() async throws {
        let computer = FakeComputer()
        let requests = Self.requests(0..<20)
        let result = try await build(computer, requests + requests)
        #expect(result.pairs == Set(requests.map { "\($0.source)\($0.destination)" }).count)
        #expect(result.computed == result.pairs)
        #expect(result.reused == 0)
        let calls = await computer.calls
        #expect(calls.count == result.pairs)
        #expect(Set(calls).count == calls.count)
        let table = try TransferWalkTable(data: result.data)
        #expect(table.count == result.pairs)
        #expect(table.graphIdentity == Self.dataset.transferWalkIdentity.value)
        #expect(table.timetableIdentity == "t1")
        for request in requests {
            let from = LocalFirstWalkingRoutingProvider.walkingEndpoint(request.source)
            let to = LocalFirstWalkingRoutingProvider.walkingEndpoint(request.destination)
            #expect(table.outcome(for: .init(from: from, to: to)) != nil)
        }
        #expect(await computer.sawNamedPoint == false)
    }

    @Test("Pafendall interchange pairs are not stored")
    func funicularPairsAreSkipped() async throws {
        let tram = Coordinate(latitude: 49.618697, longitude: 6.136686)
        let rail = Coordinate(latitude: 49.618936, longitude: 6.132919)
        let computer = FakeComputer()
        let result = try await build(computer, Self.requests(0..<6) + [WalkingRequest(source: tram, destination: rail),
                                                                       WalkingRequest(source: rail, destination: tram)])
        #expect(result.pairs == Self.requests(0..<6).count)
        let table = try TransferWalkTable(data: result.data)
        let key = TransferWalkKey(from: LocationPoint(latitude: tram.latitude, longitude: tram.longitude),
                                  to: LocationPoint(latitude: rail.latitude, longitude: rail.longitude))
        #expect(table.outcome(for: key) == nil)
    }

    @Test("An incremental build computes only new pairs and equals a full rebuild")
    func incrementalEqualsFull() async throws {
        let first = try await build(FakeComputer(), Self.requests(0..<15))
        let existing = try TransferWalkTable(data: first.data)

        let computer = FakeComputer()
        let wider = Self.requests(0..<25)
        let incremental = try await build(computer, wider, reusing: existing, timetable: "t2")
        let fresh = try await build(FakeComputer(), wider, timetable: "t2")
        #expect(incremental.data == fresh.data)
        #expect(incremental.reused == first.pairs)
        #expect(incremental.computed == fresh.pairs - first.pairs)
        #expect(await computer.calls.count == incremental.computed)
        let newTable = try TransferWalkTable(data: incremental.data)
        #expect(newTable.timetableIdentity == "t2")
        for request in Self.requests(0..<15) {
            let key = TransferWalkKey(from: LocalFirstWalkingRoutingProvider.walkingEndpoint(request.source),
                                      to: LocalFirstWalkingRoutingProvider.walkingEndpoint(request.destination))
            #expect(newTable.payload(for: key) == existing.payload(for: key))
        }
    }

    @Test("Pairs that disappeared are pruned and nothing is recomputed")
    func pruning() async throws {
        let first = try await build(FakeComputer(), Self.requests(0..<20))
        let computer = FakeComputer()
        let narrower = Self.requests(0..<10)
        let result = try await build(computer, narrower, reusing: try TransferWalkTable(data: first.data))
        #expect(result.computed == 0)
        #expect(result.pairs == narrower.count)
        #expect(await computer.calls.isEmpty)
        #expect(result.data == (try await build(FakeComputer(), narrower)).data)
    }

    @Test("A table for another graph is recomputed from scratch")
    func foreignGraphIsNotReused() async throws {
        let foreign = try TransferWalkTableCodec.encodeTable(graphIdentity: "other-graph", timetableIdentity: "t",
            entries: try TransferWalkTableCodecTests.sampleEntries(count: 5))
        let computer = FakeComputer()
        let result = try await build(computer, Self.requests(0..<8), reusing: try TransferWalkTable(data: foreign))
        #expect(result.reused == 0)
        #expect(result.computed == result.pairs)
    }

    @Test("Progress is monotonic, throttled to the missing count and ends at the total")
    func progress() async throws {
        let log = ProgressLog()
        let result = try await build(FakeComputer(), Self.requests(0..<30)) { log.record($0, $1) }
        let events = log.events
        #expect(events.first?.completed == 0)
        #expect(events.last?.completed == result.computed)
        #expect(events.allSatisfy { $0.total == result.computed })
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.completed <= $1.completed })

        let empty = ProgressLog()
        let first = try await build(FakeComputer(), Self.requests(0..<10))
        _ = try await build(FakeComputer(), Self.requests(0..<10), reusing: try TransferWalkTable(data: first.data)) { empty.record($0, $1) }
        #expect(empty.events.map(\.total) == [0])
    }

    @Test("Deterministic no-route pairs are stored; transient failures abort the build")
    func failureHandling() async throws {
        let some = FakeComputer(behavior: .noRouteFor(every: 7))
        let result = try await build(some, Self.requests(0..<30))
        #expect(result.negatives > 0)
        let table = try TransferWalkTable(data: result.data)
        #expect(table.negativeCount() == result.negatives)

        for failure in [FakeComputer.Behavior.cancelled, .datasetUnavailable, .other] {
            await #expect(throws: (any Error).self) { try await build(FakeComputer(behavior: failure), Self.requests(0..<6)) }
        }
        await #expect(throws: CancellationError.self) { try await build(FakeComputer(behavior: .cancelled), Self.requests(0..<6)) }
        await #expect(throws: WalkingRoutingError.datasetUnavailable) {
            try await build(FakeComputer(behavior: .datasetUnavailable), Self.requests(0..<6))
        }
    }

    @Test("Almost everything being unroutable is treated as a fault")
    func implausibleNegatives() async throws {
        await #expect(throws: TransferWalkBuildError.self) {
            try await build(FakeComputer(behavior: .noRouteFor(every: 1)), Self.requests(0..<30))
        }
    }

    @Test("A graph change during the build is rejected")
    func graphChanged() async throws {
        await #expect(throws: TransferWalkBuildError.graphChanged) {
            try await build(FakeComputer(active: false), Self.requests(0..<8))
        }
    }

    @Test("Cancelling mid-build returns nothing")
    func cancellation() async throws {
        let computer = FakeComputer(behavior: .slow)
        let task = Task { try await build(computer, Self.requests(0..<30)) }
        try await Task.sleep(for: .milliseconds(60))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Concurrency never exceeds the router pool size")
    func boundedConcurrency() async throws {
        let computer = FakeComputer(behavior: .slow)
        _ = try await build(computer, Self.requests(0..<8, span: 1))
        #expect(await computer.maximumConcurrent <= 4)
        #expect(await computer.maximumConcurrent >= 2)
    }
}

final class ProgressLog: @unchecked Sendable {
    struct Event: Equatable { let completed: Int; let total: Int }
    private let lock = NSLock()
    private var storage: [Event] = []
    func record(_ completed: Int, _ total: Int) { lock.withLock { storage.append(.init(completed: completed, total: total)) } }
    var events: [Event] { lock.withLock { storage } }
}

actor FakeComputer: TransferWalkComputing {
    enum Behavior { case normal, noRouteFor(every: Int), cancelled, datasetUnavailable, other, slow }
    private let behavior: Behavior
    private let active: Bool
    private(set) var calls: [TransferWalkKey] = []
    private(set) var sawNamedPoint = false
    private(set) var maximumConcurrent = 0
    private var running = 0
    struct Fault: Error {}

    init(behavior: Behavior = .normal, active: Bool = true) { self.behavior = behavior; self.active = active }

    func prepareTransferWalkComputation() async throws -> RoutingDataset { TransferWalkTableBuilderTests.dataset }
    func isActiveDataset(_ dataset: RoutingDataset) async -> Bool { active }
    func adoptTransferWalks(_ table: TransferWalkTable) async {}

    func transferWalkOutcome(from: LocationPoint, to: LocationPoint, dataset: RoutingDataset) async throws -> TransferWalkOutcome {
        calls.append(TransferWalkKey(from: from, to: to))
        if from.name != nil || to.name != nil { sawNamedPoint = true }
        running += 1; maximumConcurrent = max(maximumConcurrent, running)
        defer { running -= 1 }
        switch behavior {
        case .cancelled: throw CancellationError()
        case .datasetUnavailable: throw WalkingRoutingError.datasetUnavailable
        case .other: throw Fault()
        case .slow:
            try await Task.sleep(for: .milliseconds(25))
        case .noRouteFor(let every):
            if calls.count % every == 0 { return .noRoute }
        case .normal: break
        }
        return .route(OfflineWalkingRoute(
            distanceMeters: from.latitude + to.latitude, duration: from.longitude * 10 + to.longitude,
            coordinates: [.init(latitude: from.latitude, longitude: from.longitude), .init(latitude: to.latitude, longitude: to.longitude)],
            source: .localOSM))
    }
}
