import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

/// Proves that serving a stored transfer walk is indistinguishable from the live
/// computation, using the real bundled pedestrian graph.
@Suite("Stored transfer walks", .serialized)
struct TransferWalkEquivalenceTests {
    // Pafendall tram stop and rail station: the only pairs that use the funicular.
    static let tram = LocationPoint(latitude: 49.618697, longitude: 6.136686)
    static let rail = LocationPoint(latitude: 49.618936, longitude: 6.132919)

    static let grid: [LocationPoint] = [
        (49.6116, 6.1319), (49.6120, 6.1325), (49.6102, 6.1290), (49.6131, 6.1341),
        (49.6095, 6.1362), (49.6143, 6.1304)
    ].map { LocationPoint(latitude: $0.0, longitude: $0.1) }

    /// Thirty directed city pairs, a far pair that needs the full-reachability
    /// fallback, a pair with no road nearby, and identical endpoints.
    static var pairs: [(LocationPoint, LocationPoint)] {
        var result: [(LocationPoint, LocationPoint)] = []
        for from in grid { for to in grid where from != to { result.append((from, to)) } }
        result.append((grid[0], LocationPoint(latitude: 49.70, longitude: 6.20)))
        result.append((LocationPoint(latitude: 0, longitude: 0), grid[0]))
        result.append((grid[0], grid[0]))
        return result
    }

    @Test("A router serving stored walks returns exactly the live results")
    func storedMatchesLive() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let requests = Self.pairs.map { OfflineWalkingRequest(from: $0.0, to: $0.1) }
        let live = await fixture.router(mode: .off).routes(requests, maximumConcurrency: 4)
        #expect(live.compactMap { $0 }.count > 20)
        #expect(live.contains { $0 == nil })

        try await fixture.writeTable(for: Self.pairs)
        let stored = fixture.router(mode: .on)
        let served = await stored.routes(requests, maximumConcurrency: 4)
        #expect(served == live)
        let statistics = await stored.transferWalkStatistics()
        #expect(statistics.hits == requests.count)
        #expect(statistics.misses == 0)

        // The package-facing mapping is identical as well, bit for bit.
        let provider = LocalFirstWalkingRoutingProvider(walkingRouter: stored)
        let reference = LocalFirstWalkingRoutingProvider(walkingRouter: fixture.router(mode: .off))
        let walkingRequests = Self.pairs.map {
            WalkingRequest(source: .init(latitude: $0.0.latitude, longitude: $0.0.longitude),
                           destination: .init(latitude: $0.1.latitude, longitude: $0.1.longitude))
        }
        #expect(await provider.routes(walkingRequests, maximumConcurrency: 4)
            == (await reference.routes(walkingRequests, maximumConcurrency: 4)))
    }

    @Test("Pafendall interchange pairs are never stored and stay live")
    func funicularPairsStayLive() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let funicular = [(Self.tram, Self.rail), (Self.rail, Self.tram)]
        let requests = funicular.map { OfflineWalkingRequest(from: $0.0, to: $0.1) }
        let live = await fixture.router(mode: .off).routes(requests, maximumConcurrency: 2)
        #expect(live.allSatisfy { $0?.source == .stationConnection && $0?.segments.isEmpty == false })

        try await fixture.writeTable(for: Self.pairs + funicular)
        let stored = fixture.router(mode: .on)
        #expect(await stored.routes(requests, maximumConcurrency: 2) == live)
        let statistics = await stored.transferWalkStatistics()
        #expect(statistics.hits == 0)
        #expect(statistics.misses == 2)
    }

    @Test("Named points and single route calls never consult the table")
    func onlyUnnamedBatchHits() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let pair = Self.pairs[0]
        try await fixture.writeTable(for: [pair])
        let stored = fixture.router(mode: .on)

        _ = try await stored.route(from: pair.0, to: pair.1)
        #expect(await stored.transferWalkStatistics().hits == 0)

        let named = [OfflineWalkingRequest(
            from: LocationPoint(name: "Named", latitude: pair.0.latitude, longitude: pair.0.longitude),
            to: LocationPoint(name: "Other", latitude: pair.1.latitude, longitude: pair.1.longitude))]
        let second = fixture.router(mode: .on)
        _ = await second.routes(named, maximumConcurrency: 1)
        #expect(await second.transferWalkStatistics().hits == 0)
    }

    @Test("A single full-search walk followed by a batch behaves the same with and without the table")
    func callOrderIsUnchanged() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try await fixture.writeTable(for: Self.pairs)
        let subset = Array(Self.pairs.prefix(6))
        let requests = subset.map { OfflineWalkingRequest(from: $0.0, to: $0.1) }

        var outputs: [[OfflineWalkingRoute?]] = []
        for mode in [TransferWalkMode.off, .on] {
            let router = fixture.router(mode: mode)
            for pair in subset { _ = try? await router.route(from: pair.0, to: pair.1) }
            outputs.append(await router.routes(requests, maximumConcurrency: 4))
        }
        #expect(outputs[0] == outputs[1])
    }

    @Test("A table from another graph is ignored")
    func foreignGraphIsIgnored() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let entries = try await fixture.entries(for: [Self.pairs[0]])
        try fixture.store.write(try TransferWalkTableCodec.encodeTable(
            graphIdentity: "someone-else", timetableIdentity: nil, entries: entries))
        let router = fixture.router(mode: .on)
        _ = await router.routes([OfflineWalkingRequest(from: Self.pairs[0].0, to: Self.pairs[0].1)], maximumConcurrency: 1)
        let statistics = await router.transferWalkStatistics()
        #expect(statistics.hits == 0)
        #expect(statistics.misses == 0)
        // The foreign file is kept for its own graph.
        guard case .table = fixture.store.load() else { Issue.record("foreign table was removed"); return }
    }

    @Test("A corrupt table is discarded and routing continues live")
    func corruptTableIsDiscarded() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try fixture.store.write(Data("not a table".utf8))
        let router = fixture.router(mode: .on)
        let result = await router.routes([OfflineWalkingRequest(from: Self.pairs[0].0, to: Self.pairs[0].1)], maximumConcurrency: 1)
        #expect(result.first??.source == .localOSM)
        guard case .missing = fixture.store.load() else { Issue.record("corrupt file should be gone"); return }
    }

    @Test("Verify mode agrees with a correct table")
    func verifyModeAgrees() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try await fixture.writeTable(for: Array(Self.pairs.prefix(8)))
        let router = fixture.router(mode: .verify)
        let requests = Self.pairs.prefix(8).map { OfflineWalkingRequest(from: $0.0, to: $0.1) }
        let live = await fixture.router(mode: .off).routes(requests, maximumConcurrency: 4)
        #expect(await router.routes(requests, maximumConcurrency: 4) == live)
        #expect(await router.transferWalkStatistics().hits == 8)
    }

    @Test("Strict computation rethrows cancellation and a missing graph instead of storing no route")
    func strictModeRejectsTransientFailures() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let router = fixture.router(mode: .off)
        let dataset = try await router.prepareTransferWalkComputation()
        let pair = Self.pairs[0]

        let cancelled = Task { try await router.transferWalkOutcome(from: pair.0, to: pair.1, dataset: dataset) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        let missing = RoutingDataset(manifest: dataset.manifest,
            tileArchiveURL: fixture.folder.appendingPathComponent("missing.tar"), storageRevision: "missing-\(UUID().uuidString)")
        await #expect(throws: WalkingRoutingError.datasetUnavailable) {
            try await router.transferWalkOutcome(from: pair.0, to: pair.1, dataset: missing)
        }

        // A deterministic failure is a stored no-route; a routable pair is a route.
        #expect(try await router.transferWalkOutcome(from: Self.pairs[Self.pairs.count - 2].0,
                                                      to: Self.pairs[Self.pairs.count - 2].1, dataset: dataset) == .noRoute)
        guard case .route = try await router.transferWalkOutcome(from: pair.0, to: pair.1, dataset: dataset) else {
            Issue.record("expected a route"); return
        }
    }

    @Test("A table built by the real builder is served identically and adopted live")
    func builtTableMatchesLive() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let city = Array(Self.pairs.prefix(30)) + [(Self.pairs[Self.pairs.count - 2])]
        let requests = city.map {
            WalkingRequest(source: .init(latitude: $0.0.latitude, longitude: $0.0.longitude),
                           destination: .init(latitude: $0.1.latitude, longitude: $0.1.longitude))
        }
        let computer = fixture.router(mode: .on)
        let dataset = try await computer.prepareTransferWalkComputation()
        let result = try await TransferWalkTableBuilder(computer: computer).build(
            requests: requests, dataset: dataset, reusing: nil, timetableIdentity: "tt", progress: { _, _ in })
        #expect(result.pairs == city.count)
        #expect(result.negatives == 1)
        try fixture.store.write(result.data)
        guard case .table(let table) = fixture.store.load() else { Issue.record("table did not load"); return }

        // The running router adopts the new table without a restart.
        await computer.adoptTransferWalks(table)
        let offline = city.map { OfflineWalkingRequest(from: $0.0, to: $0.1) }
        let served = await computer.routes(offline, maximumConcurrency: 4)
        #expect(await computer.transferWalkStatistics().hits == city.count)
        let live = await fixture.router(mode: .off).routes(offline, maximumConcurrency: 4)
        #expect(served == live)

        // A second build against the stored table recomputes nothing.
        let again = try await TransferWalkTableBuilder(computer: computer).build(
            requests: requests, dataset: dataset, reusing: table, timetableIdentity: "tt", progress: { _, _ in })
        #expect(again.computed == 0)
        #expect(again.data == result.data)
    }

    @Test("Only request-determined failures may be stored as no route")
    func classifier() {
        #expect(TransferWalkErrorClassifier.isDeterministic(WalkingRoutingError.noRoute))
        #expect(TransferWalkErrorClassifier.isDeterministic(WalkingRoutingError.invalidResponse))
        #expect(TransferWalkErrorClassifier.isDeterministic(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))))
        #expect(!TransferWalkErrorClassifier.isDeterministic(WalkingRoutingError.datasetUnavailable))
        #expect(!TransferWalkErrorClassifier.isDeterministic(CancellationError()))
        #expect(!TransferWalkErrorClassifier.isDeterministic(URLError(.cancelled)))
    }

    // MARK: Fixture

    struct Fixture {
        let folder: URL
        let manager: RoutingDatasetManager
        let store: TransferWalkStore

        static func make() async throws -> Fixture {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("TransferWalkEquivalence-\(UUID().uuidString)", isDirectory: true)
            let manager = RoutingDatasetManager(rootURL: folder.appendingPathComponent("graph"), appBuild: 10)
            let state = await BundledRoutingDatasetInstaller(datasetManager: manager).installIfNeeded()
            guard case .ready = state else {
                try? FileManager.default.removeItem(at: folder)
                throw Skip("Bundled walking graph unavailable")
            }
            return Fixture(folder: folder, manager: manager,
                           store: TransferWalkStore(directoryURL: folder.appendingPathComponent("transfer-walks")))
        }

        struct Skip: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

        func cleanUp() { try? FileManager.default.removeItem(at: folder) }

        func router(mode: TransferWalkMode) -> LocalFirstWalkingRouter {
            LocalFirstWalkingRouter(datasetManager: manager, transferWalkStore: store, transferWalkMode: mode)
        }

        /// Computes entries exactly as a table build does: strict, short search, unnamed
        /// points, skipping Pafendall pairs.
        func entries(for pairs: [(LocationPoint, LocationPoint)]) async throws -> [(key: TransferWalkKey, payload: Data)] {
            let computer = router(mode: .off)
            let dataset = try await computer.prepareTransferWalkComputation()
            var byKey: [TransferWalkKey: Data] = [:]
            for (from, to) in pairs where PafendallFunicularConnection.terminals(from: from, to: to) == nil {
                let outcome = try await computer.transferWalkOutcome(from: from, to: to, dataset: dataset)
                byKey[TransferWalkKey(from: from, to: to)] = try TransferWalkTableCodec.encodePayload(outcome)
            }
            return byKey.map { (key: $0.key, payload: $0.value) }.sorted { $0.key < $1.key }
        }

        func writeTable(for pairs: [(LocationPoint, LocationPoint)]) async throws {
            let dataset = try #require(try await manager.activeDataset())
            try store.write(try TransferWalkTableCodec.encodeTable(
                graphIdentity: dataset.transferWalkIdentity.value, timetableIdentity: "test-timetable",
                entries: try await entries(for: pairs)))
        }
    }
}
