import CryptoKit
import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Transfer walk table format")
struct TransferWalkTableCodecTests {
    @Test("Routes round-trip bit for bit")
    func routeRoundTrip() throws {
        let route = OfflineWalkingRoute(
            distanceMeters: 123.456789012345, duration: 98.7654321,
            coordinates: [.init(latitude: 49.6116, longitude: 6.1319), .init(latitude: 49.612000000001, longitude: 6.1325)],
            source: .localOSM)
        let decoded = try TransferWalkTableCodec.decodePayload(try TransferWalkTableCodec.encodePayload(.route(route)))
        guard case .route(let result) = decoded else { Issue.record("expected route"); return }
        #expect(result.distanceMeters.bitPattern == route.distanceMeters.bitPattern)
        #expect(result.duration.bitPattern == route.duration.bitPattern)
        #expect(result.coordinates.map(\.latitude.bitPattern) == route.coordinates.map(\.latitude.bitPattern))
        #expect(result.coordinates.map(\.longitude.bitPattern) == route.coordinates.map(\.longitude.bitPattern))
        #expect(result.source == .localOSM)
        #expect(result.segments.isEmpty)
    }

    @Test("Edge doubles keep their exact bit patterns")
    func edgeValues() throws {
        for value in [0.0, -0.0, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude, 0.1 + 0.2] {
            let route = OfflineWalkingRoute(distanceMeters: value, duration: value,
                coordinates: [.init(latitude: value, longitude: value)], source: .localOSM)
            guard case .route(let result) = try TransferWalkTableCodec.decodePayload(
                try TransferWalkTableCodec.encodePayload(.route(route))) else { Issue.record("expected route"); return }
            #expect(result.distanceMeters.bitPattern == value.bitPattern)
            #expect(result.coordinates[0].latitude.bitPattern == value.bitPattern)
        }
    }

    @Test("An empty polyline and a negative entry survive")
    func emptyAndNegative() throws {
        let empty = OfflineWalkingRoute(distanceMeters: 1, duration: 2, coordinates: [], source: .localOSM)
        #expect(try TransferWalkTableCodec.decodePayload(try TransferWalkTableCodec.encodePayload(.route(empty))) == .route(empty))
        #expect(try TransferWalkTableCodec.decodePayload(try TransferWalkTableCodec.encodePayload(.noRoute)) == .noRoute)
    }

    @Test("Station connection segments are refused")
    func segmentsAreRefused() {
        let segment = WalkingRouteSegment(mode: .walking, durationSeconds: 1, distanceMeters: 1, polyline: [])
        let route = OfflineWalkingRoute(distanceMeters: 1, duration: 2, coordinates: [], source: .stationConnection,
                                        segments: [segment])
        #expect(throws: TransferWalkTableError.unsupported("segments")) {
            try TransferWalkTableCodec.encodePayload(.route(route))
        }
    }

    @Test("Payload decoding rejects trailing bytes, truncation and bad codes")
    func malformedPayloads() throws {
        let route = OfflineWalkingRoute(distanceMeters: 1, duration: 2,
            coordinates: [.init(latitude: 1, longitude: 2)], source: .localOSM)
        let good = try TransferWalkTableCodec.encodePayload(.route(route))
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(good + Data([0])) }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(good.dropLast()) }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(Data([7])) }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(Data()) }
        var badSource = good
        badSource[17] = 9
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(badSource) }
        var hugeCount = good
        hugeCount.replaceSubrange(18..<22, with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTableCodec.decodePayload(hugeCount) }
    }

    @Test("A table finds every key and misses absent ones")
    func tableLookup() throws {
        let entries = try Self.sampleEntries(count: 257)
        let table = try TransferWalkTable(data: try TransferWalkTableCodec.encodeTable(
            graphIdentity: "graph-é", timetableIdentity: "gtfs-1", entries: entries))
        #expect(table.count == 257)
        #expect(table.graphIdentity == "graph-é")
        #expect(table.timetableIdentity == "gtfs-1")
        for entry in entries {
            #expect(table.payload(for: entry.key) == entry.payload)
            #expect(table.outcome(for: entry.key) != nil)
        }
        #expect(table.outcome(for: Self.key(0)) == nil)
        #expect(table.outcome(for: Self.key(10_000)) == nil)
        #expect(table.negativeCount() == (1...257).filter { ($0 - 1) % 5 == 0 }.count)
    }

    @Test("An empty table and a missing timetable identity are valid")
    func emptyTable() throws {
        let table = try TransferWalkTable(data: try TransferWalkTableCodec.encodeTable(
            graphIdentity: "g", timetableIdentity: nil, entries: []))
        #expect(table.count == 0)
        #expect(table.timetableIdentity == nil)
        #expect(table.outcome(for: Self.key(1)) == nil)
    }

    @Test("Encoding is deterministic and unsorted input is refused")
    func determinism() throws {
        let entries = try Self.sampleEntries(count: 40)
        let first = try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t", entries: entries)
        let second = try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t", entries: entries)
        #expect(first == second)
        #expect(throws: TransferWalkTableError.self) {
            try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t", entries: entries.reversed())
        }
        let duplicate = [entries[0], entries[0]]
        #expect(throws: TransferWalkTableError.self) {
            try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t", entries: duplicate)
        }
    }

    @Test("Corruption anywhere in the file is rejected")
    func corruption() throws {
        let data = try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t",
                                                          entries: try Self.sampleEntries(count: 20))
        for position in [0, 5, 20, data.count / 2, data.count - 40, data.count - 1] {
            var flipped = data
            flipped[position] ^= 0x01
            #expect(throws: TransferWalkTableError.self) { try TransferWalkTable(data: flipped) }
        }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTable(data: data.dropLast()) }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTable(data: Data(data.prefix(10))) }
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTable(data: Data()) }
    }

    @Test("A structurally invalid file with a valid checksum is still rejected")
    func structuralValidation() throws {
        let entries = try Self.sampleEntries(count: 6)
        var data = try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: "t", entries: entries)
        // Swap the first two index entries, then repair the checksum.
        let indexStart = TransferWalkTableCodec.headerFixedSize + 1 + 1
        let size = TransferWalkTableCodec.indexEntrySize
        let first = data.subdata(in: indexStart..<(indexStart + size)), second = data.subdata(in: (indexStart + size)..<(indexStart + 2 * size))
        data.replaceSubrange(indexStart..<(indexStart + size), with: second)
        data.replaceSubrange((indexStart + size)..<(indexStart + 2 * size), with: first)
        let body = data.prefix(data.count - 32)
        let repaired = Data(body) + Data(SHA256.hash(data: body))
        #expect(throws: TransferWalkTableError.self) { try TransferWalkTable(data: repaired) }
    }

    @Test("The header can be read without loading the table")
    func headerOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TransferWalkHeader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TransferWalkStore(directoryURL: folder)
        #expect(store.header() == nil)
        guard case .missing = store.load() else { Issue.record("expected missing"); return }
        try store.write(try TransferWalkTableCodec.encodeTable(graphIdentity: "graph", timetableIdentity: "tt",
                                                               entries: try Self.sampleEntries(count: 3)))
        #expect(store.header() == .init(graphIdentity: "graph", timetableIdentity: "tt", entryCount: 3))
        guard case .table(let table) = store.load() else { Issue.record("expected table"); return }
        #expect(table.count == 3)
    }

    @Test("Only the file that failed validation is discarded")
    func guardedDiscard() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TransferWalkDiscard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TransferWalkStore(directoryURL: folder)
        try store.write(Data("not a table".utf8))
        guard case .invalid(let stamp) = store.load() else { Issue.record("expected invalid"); return }
        // A valid table replaces it before the stale decision runs.
        try store.write(try TransferWalkTableCodec.encodeTable(graphIdentity: "g", timetableIdentity: nil, entries: []))
        store.discard(ifStillMatching: stamp)
        guard case .table = store.load() else { Issue.record("valid table was discarded"); return }
        try store.write(Data("garbage".utf8))
        guard case .invalid(let second) = store.load() else { Issue.record("expected invalid"); return }
        store.discard(ifStillMatching: second)
        guard case .missing = store.load() else { Issue.record("invalid file should be gone"); return }
    }

    @Test("Keys compare lexicographically and match bit patterns")
    func keyOrdering() {
        let a = TransferWalkKey(from: .init(latitude: 49.6, longitude: 6.1), to: .init(latitude: 49.7, longitude: 6.2))
        let b = TransferWalkKey(from: .init(latitude: 49.6, longitude: 6.1), to: .init(latitude: 49.7, longitude: 6.2))
        #expect(a == b)
        #expect(a.fromLatitudeBits == (49.6 as Double).bitPattern)
        let c = TransferWalkKey(from: .init(latitude: 49.6, longitude: 6.1), to: .init(latitude: 49.7, longitude: 6.2.nextUp))
        #expect(a != c)
        #expect(a < c || c < a)
    }

    @Test("Graph identity covers every result-affecting input")
    func graphIdentity() {
        let base = Self.manifest(version: "v1", sha: "ABC")
        let identity = base.transferWalkIdentity.value
        #expect(identity == Self.manifest(version: "v1", sha: "abc").transferWalkIdentity.value)
        #expect(identity != Self.manifest(version: "v2", sha: "abc").transferWalkIdentity.value)
        #expect(identity != Self.manifest(version: "v1", sha: "def").transferWalkIdentity.value)
        #expect(identity != Self.manifest(version: "v1", sha: "abc", core: "other").transferWalkIdentity.value)
        #expect(identity.contains("alg=\(TransferWalkGraphIdentity.algorithmRevision)"))
        #expect(identity.contains(PafendallFunicularConnection.revision))
    }

    // MARK: Helpers

    static func key(_ index: Int) -> TransferWalkKey {
        .init(fromLatitudeBits: UInt64(1_000 + index / 7), fromLongitudeBits: UInt64(index % 7),
              toLatitudeBits: UInt64(index), toLongitudeBits: UInt64(index * 3))
    }

    static func sampleEntries(count: Int) throws -> [(key: TransferWalkKey, payload: Data)] {
        try (1...count).map { index in
            let outcome: TransferWalkOutcome = (index - 1) % 5 == 0 ? .noRoute : .route(OfflineWalkingRoute(
                distanceMeters: Double(index) * 1.5, duration: Double(index) * 2.25,
                coordinates: (0..<(index % 4)).map { .init(latitude: 49 + Double($0) / 3, longitude: 6 + Double(index) / 7) },
                source: .localOSM))
            return (key: key(index), payload: try TransferWalkTableCodec.encodePayload(outcome))
        }.sorted { $0.key < $1.key }
    }

    static func manifest(version: String, sha: String, core: String = "core") -> RoutingDatasetManifest {
        .init(schemaVersion: 1, region: "luxembourg", datasetVersion: version,
              routingEngine: .init(valhallaMobileVersion: RoutingDatasetManager.valhallaMobileVersion, valhallaCoreCommit: core),
              artifact: .init(url: URL(string: "https://example.invalid/tiles.tar")!, sizeBytes: 1, sha256: sha),
              minimumAppBuild: 1)
    }
}
