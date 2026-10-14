import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Routing optimisation decision")
struct RoutingOptimisationDecisionTests {
    typealias Inputs = RoutingOptimisationInputs
    static func header(_ graph: String, _ timetable: String?) -> TransferWalkTable.Header {
        .init(graphIdentity: graph, timetableIdentity: timetable, entryCount: 1)
    }
    static func inputs(mode: TransferWalkMode = .on, active: String? = "G", pending: String? = nil, timetable: String? = "T",
                       header: TransferWalkTable.Header? = nil, blocked: Bool = false) -> Inputs {
        .init(mode: mode, activeGraph: active, pendingBundledGraph: pending, timetable: timetable, header: header, blockedByLedger: blocked)
    }

    @Test("Every row of the decision table", arguments: [
        (inputs(mode: .off), RoutingOptimisationRequirement.notNeeded),
        (inputs(active: nil), .notNeeded),
        (inputs(timetable: nil), .waitingForTimetable),
        (inputs(timetable: nil, header: header("G", "T")), .notNeeded),
        (inputs(timetable: nil, header: header("OLD", "T")), .waitingForTimetable),
        (inputs(header: nil), .needsFull),
        (inputs(header: header("OLD", "T")), .needsFull),
        (inputs(header: header("G", "OLD")), .needsIncremental),
        (inputs(header: header("G", nil)), .needsIncremental),
        (inputs(header: header("G", "T")), .notNeeded),
        (inputs(mode: .verify, header: nil), .needsFull),
        (inputs(header: nil, blocked: true), .notNeeded),
        (inputs(header: header("G", "OLD"), blocked: true), .notNeeded),
        (inputs(timetable: nil, blocked: true), .waitingForTimetable),
        // A pending bundled graph replaces the active one as the expected graph.
        (inputs(pending: "NEW", header: header("G", "T")), .needsFull),
        (inputs(pending: "NEW", header: header("NEW", "T")), .notNeeded),
        (inputs(active: nil, pending: "NEW", timetable: nil), .waitingForTimetable)
    ])
    func decisionTable(inputs: Inputs, expected: RoutingOptimisationRequirement) {
        #expect(RoutingOptimisationDecision.requirement(inputs) == expected)
    }
}

@Suite("Transfer walk settings")
struct TransferWalkSettingsTests {
    @Test("The test host never touches the real store")
    func testHostDisablesStoredWalks() {
        #expect(TransferWalkSettings.isTestHost)
        #expect(TransferWalkSettings.mode == .off)
    }
}

@Suite("Routing optimisation", .serialized)
struct RoutingOptimisationServiceTests {
    // MARK: Launch check on disk

    @Test("The launch check reads the active graph, bundled graph, timetable and table header")
    func launchCheckOnDisk() throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        // Nothing installed at all.
        #expect(fixture.launchRequirement() == .notNeeded)

        try fixture.installGraph(version: "v1", sha: "aaa")
        #expect(fixture.launchRequirement() == .waitingForTimetable)

        try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        #expect(fixture.launchRequirement() == .needsFull)

        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        #expect(fixture.launchRequirement() == .notNeeded)

        try fixture.installTimetable(filename: "gtfs-generation-2-B.sqlite")
        #expect(fixture.launchRequirement() == .needsIncremental)
    }

    @Test("A pending bundled graph expects a new table, unless its installation already failed")
    func pendingBundledGraph() throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        #expect(fixture.launchRequirement() == .notNeeded)

        try fixture.writeBundledManifest(version: "v2", sha: "bbb")
        #expect(fixture.launchRequirement() == .needsFull)

        // Same version as the active graph: never pending, whatever the sha.
        try fixture.writeBundledManifest(version: "v1", sha: "zzz")
        #expect(fixture.launchRequirement() == .notNeeded)

        // An installation that failed is remembered and no longer expected.
        let bundled = TransferWalkTableCodecTests.manifest(version: "v2", sha: "bbb")
        try fixture.writeBundledManifest(version: "v2", sha: "bbb")
        fixture.environment.ledger.recordBundledInstall(.failed(previousVersionStillAvailable: true),
            identity: RoutingOptimisationLaunchCheck.bundledInstallIdentity(bundled))
        #expect(fixture.launchRequirement() == .notNeeded)
        fixture.environment.ledger.recordBundledInstall(.ready(version: "v2"), identity: nil)
        #expect(fixture.launchRequirement() == .needsFull)
    }

    @Test("An expired timetable never interrupts a launch that already has a table")
    func expiredTimetable() throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite", validThrough: "2020-01-01")
        #expect(fixture.launchRequirement() == .waitingForTimetable)
        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        #expect(fixture.launchRequirement() == .notNeeded)
    }

    @Test("Two unfinished attempts stop further attempts for that target only")
    func ledger() throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        let ledger = fixture.environment.ledger
        ledger.recordStart(for: "a")
        #expect(!ledger.isBlocked(target: "a"))
        ledger.recordStart(for: "a")
        #expect(ledger.isBlocked(target: "a"))
        #expect(!ledger.isBlocked(target: "b"))
        ledger.recordStart(for: "b")
        #expect(ledger.attempts(for: "a") == 0)
        ledger.recordAbandoned(for: "b")
        #expect(ledger.attempts(for: "b") == 0)
        ledger.recordStart(for: "b"); ledger.recordFinish(for: "b")
        #expect(ledger.attempts(for: "b") == 0)
    }

    // MARK: Service

    @Test("A full run writes a table that satisfies the launch check, then a timetable change is incremental")
    func fullThenIncremental() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let first = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        let computer = FakeComputer()
        let service = fixture.service(computer: computer, database: first, pairs: 0..<14)
        #expect(await service.requirement() == .needsFull)

        let log = ProgressLog()
        try await service.optimise { log.record(Int($0.fraction * 100), 100) }
        let firstPairs = await computer.calls.count
        #expect(firstPairs == TransferWalkTableBuilderTests.requests(0..<14).count)
        #expect(log.events.last?.completed == 100)
        #expect(zip(log.events, log.events.dropFirst()).allSatisfy { $0.completed <= $1.completed })
        #expect(fixture.launchRequirement() == .notNeeded)
        #expect(fixture.environment.ledger.attempts(for: fixture.target(timetable: "gtfs-generation-1-A.sqlite")) == 0)
        #expect(fixture.environment.store.header()?.timetableIdentity == "gtfs-generation-1-A.sqlite")

        // A new timetable with more pairs only computes the new ones.
        let second = try fixture.installTimetable(filename: "gtfs-generation-2-B.sqlite")
        let incrementalComputer = FakeComputer()
        let incremental = fixture.service(computer: incrementalComputer, database: second, pairs: 0..<20)
        #expect(await incremental.requirement() == .needsIncremental)
        try await incremental.optimise { _ in }
        let wanted = TransferWalkTableBuilderTests.requests(0..<20).count
        #expect(await incrementalComputer.calls.count == wanted - firstPairs)
        #expect(fixture.launchRequirement() == .notNeeded)
        #expect(await incremental.requirement() == .notNeeded)
    }

    @Test("A run that is not needed finishes at once without computing")
    func noWorkRun() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let database = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        let computer = FakeComputer()
        let log = ProgressLog()
        try await fixture.service(computer: computer, database: database).optimise { log.record(Int($0.fraction * 100), 100) }
        #expect(await computer.calls.isEmpty)
        #expect(log.events.last?.completed == 100)
    }

    @Test("A second caller joins the run in flight instead of starting another")
    func joinsRunInFlight() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let database = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        let computer = FakeComputer(behavior: .slow)
        let service = fixture.service(computer: computer, database: database, pairs: 0..<10)
        let firstLog = ProgressLog(), secondLog = ProgressLog()
        async let first: Void = service.optimise { firstLog.record(Int($0.fraction * 100), 100) }
        try await Task.sleep(for: .milliseconds(80))
        async let second: Void = service.optimise { secondLog.record(Int($0.fraction * 100), 100) }
        try await first
        try await second
        #expect(await computer.calls.count == TransferWalkTableBuilderTests.requests(0..<10).count)
        #expect(firstLog.events.last?.completed == 100)
        #expect(secondLog.events.last?.completed == 100)
        #expect(!secondLog.events.isEmpty)
    }

    @Test("A failed run keeps the old table, counts the attempt and blocks after two")
    func failureKeepsOldTable() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let first = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        let before = try Data(contentsOf: fixture.environment.store.fileURL)
        let second = try fixture.installTimetable(filename: "gtfs-generation-2-B.sqlite")
        _ = first

        let service = fixture.service(computer: FakeComputer(behavior: .other), database: second, pairs: 0..<10)
        await #expect(throws: (any Error).self) { try await service.optimise { _ in } }
        #expect(try Data(contentsOf: fixture.environment.store.fileURL) == before)
        let target = fixture.target(timetable: "gtfs-generation-2-B.sqlite")
        #expect(fixture.environment.ledger.attempts(for: target) == 1)
        #expect(fixture.launchRequirement() == .needsIncremental)

        await #expect(throws: (any Error).self) { try await service.optimise { _ in } }
        #expect(fixture.environment.ledger.attempts(for: target) == 2)
        #expect(fixture.launchRequirement() == .notNeeded)
    }

    @Test("A stalled build is stopped and reported")
    func stalledBuild() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let database = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        let service = fixture.service(computer: FakeComputer(behavior: .hang), database: database, pairs: 0..<6,
                                      stallTimeout: .milliseconds(400))
        await #expect(throws: RoutingOptimisationError.stalled) { try await service.optimise { _ in } }
        #expect(fixture.environment.ledger.attempts(for: fixture.target(timetable: "gtfs-generation-1-A.sqlite")) == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.environment.store.fileURL.path))
    }

    @Test("A corrupt table is replaced by a full build")
    func corruptTable() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        let database = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        try fixture.environment.store.write(Data("garbage that is not a table".utf8))
        #expect(fixture.launchRequirement() == .needsFull)
        let computer = FakeComputer()
        try await fixture.service(computer: computer, database: database, pairs: 0..<8).optimise { _ in }
        #expect(await computer.calls.count == TransferWalkTableBuilderTests.requests(0..<8).count)
        guard case .table = fixture.environment.store.load() else { Issue.record("table was not rebuilt"); return }
    }

    @Test("Waiting for the first timetable ends when one is installed")
    func waitsForTimetable() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        #expect(fixture.launchRequirement() == .waitingForTimetable)
        let timetable = FakeTimetable()
        let service = fixture.service(computer: FakeComputer(), timetable: timetable, pairs: 0..<6, pollInterval: .milliseconds(20))
        let waiting = Task { await service.waitForTimetable() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await timetable.refreshCalls == 1)
        let database = try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        await timetable.install(database)
        await waiting.value
        try await service.optimise { _ in }
        #expect(fixture.launchRequirement() == .notNeeded)
    }

    @Test("Waiting stops when the caller is cancelled")
    func waitingIsCancellable() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(computer: FakeComputer(), timetable: FakeTimetable(), pairs: 0..<2, pollInterval: .milliseconds(20))
        let waiting = Task { await service.waitForTimetable() }
        try await Task.sleep(for: .milliseconds(60))
        waiting.cancel()
        await waiting.value
    }

    @Test("The graph installation result is recorded before the requirement is evaluated")
    func installResultIsRecorded() async throws {
        let fixture = try OptimisationFixture()
        defer { fixture.cleanUp() }
        try fixture.installGraph(version: "v1", sha: "aaa")
        try fixture.installTimetable(filename: "gtfs-generation-1-A.sqlite")
        try fixture.writeTable(graph: "v1", sha: "aaa", timetable: "gtfs-generation-1-A.sqlite")
        try fixture.writeBundledManifest(version: "v2", sha: "bbb")
        #expect(fixture.launchRequirement() == .needsFull)
        // The install fails, leaving v1 active; the table for v1 is still current.
        let install = Task { RoutingDataState.failed(previousVersionStillAvailable: true) }
        let service = fixture.service(computer: FakeComputer(), pairs: 0..<4, graphInstall: install)
        #expect(await service.requirement() == .notNeeded)
        #expect(fixture.launchRequirement() == .notNeeded)
    }
}

// MARK: Support

struct OptimisationFixture {
    let folder: URL
    let defaults: UserDefaults
    let suite: String
    var environment: RoutingOptimisationEnvironment

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RoutingOptimisation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "RoutingOptimisationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        environment = RoutingOptimisationEnvironment(
            mode: .on, routingRootURL: folder.appendingPathComponent("Routing"),
            gtfsDirectoryURL: folder.appendingPathComponent("Mobiliteit"),
            bundledManifestURL: folder.appendingPathComponent("bundled-manifest.json"),
            store: TransferWalkStore(directoryURL: folder.appendingPathComponent("transfer-walks")),
            ledger: RoutingOptimisationAttemptLedger(defaults: defaults), appBuild: 10)
        try FileManager.default.createDirectory(at: environment.gtfsDirectoryURL, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    func launchRequirement() -> RoutingOptimisationRequirement { RoutingOptimisationLaunchCheck.requirement(in: environment) }

    func target(timetable: String) -> String {
        RoutingOptimisationLaunchCheck.target(
            graph: TransferWalkTableCodecTests.manifest(version: "v1", sha: "aaa").transferWalkIdentity.value, timetable: timetable)
    }

    func installGraph(version: String, sha: String) throws {
        let directory = environment.routingRootURL.appendingPathComponent("versions/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("tiles".utf8).write(to: directory.appendingPathComponent("tiles.tar"))
        try JSONEncoder.routing.encode(TransferWalkTableCodecTests.manifest(version: version, sha: sha))
            .write(to: directory.appendingPathComponent("manifest.json"))
        try Data(#"{"version":"\#(version)"}"#.utf8).write(to: environment.routingRootURL.appendingPathComponent("current.json"))
    }

    func writeBundledManifest(version: String, sha: String) throws {
        try JSONEncoder.routing.encode(TransferWalkTableCodecTests.manifest(version: version, sha: sha))
            .write(to: environment.bundledManifestURL!)
    }

    @discardableResult
    func installTimetable(filename: String, validThrough: String = "2099-12-31") throws -> URL {
        let metadata: [String: Any] = ["resourceID": "r", "resourceTitle": "t", "downloadedAt": 0, "lastCheckedAt": 0,
            "generation": 1, "validThrough": validThrough, "databaseFilename": filename]
        try JSONSerialization.data(withJSONObject: metadata)
            .write(to: environment.gtfsDirectoryURL.appendingPathComponent("metadata.json"))
        let database = environment.gtfsDirectoryURL.appendingPathComponent(filename)
        try Data("db".utf8).write(to: database)
        return database
    }

    func writeTable(graph version: String, sha: String, timetable: String) throws {
        let identity = TransferWalkTableCodecTests.manifest(version: version, sha: sha).transferWalkIdentity.value
        try environment.store.write(try TransferWalkTableCodec.encodeTable(
            graphIdentity: identity, timetableIdentity: timetable, entries: try TransferWalkTableCodecTests.sampleEntries(count: 3)))
    }

    func service(computer: FakeComputer, database: URL? = nil, timetable: FakeTimetable? = nil, pairs: Range<Int> = 0..<6,
                 stallTimeout: Duration = .seconds(60), pollInterval: Duration = .milliseconds(20),
                 graphInstall: Task<RoutingDataState, Never>? = nil) -> TransferWalkOptimisationService {
        let provider = timetable ?? FakeTimetable(url: database)
        return TransferWalkOptimisationService(
            environment: environment, computer: computer, timetable: provider,
            transferRequests: { _ in TransferWalkTableBuilderTests.requests(pairs) },
            graphInstall: graphInstall, stallTimeout: stallTimeout, pollInterval: pollInterval)
    }

    func service(computer: FakeComputer, pairs: Range<Int>, graphInstall: Task<RoutingDataState, Never>?) -> TransferWalkOptimisationService {
        service(computer: computer, database: environment.gtfsDirectoryURL.appendingPathComponent("gtfs-generation-1-A.sqlite"),
                pairs: pairs, graphInstall: graphInstall)
    }
}

actor FakeTimetable: RoutingTimetableProviding {
    private var url: URL?
    private(set) var refreshCalls = 0
    init(url: URL? = nil) { self.url = url }
    func install(_ url: URL) { self.url = url }
    func routingDatabaseURL() async -> URL? { url }
    func refreshIfNeeded(force: Bool) async -> GTFSFeedStatus { refreshCalls += 1; return .unavailable }
}
