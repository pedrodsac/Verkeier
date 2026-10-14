import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

/// Exhaustive check on an installed timetable: every transfer pair RAPTOR can
/// request is identical whether it is served from the table or computed live.
/// Needs a real feed, so it only runs when `ROUTING_TEST_FEED_DIR` points at a
/// folder with a GTFS `*.sqlite` (pass it as `TEST_RUNNER_ROUTING_TEST_FEED_DIR`).
@Suite("Stored transfer walks on the installed feed", .serialized)
struct TransferWalkRealFeedEquivalenceTests {
    static var feedDirectory: URL? {
        ProcessInfo.processInfo.environment["ROUTING_TEST_FEED_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @Test("Every transfer pair is identical stored and live",
          .enabled(if: TransferWalkRealFeedEquivalenceTests.feedDirectory != nil))
    func everyPairMatches() async throws {
        let directory = try #require(Self.feedDirectory)
        let database = try #require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sqlite" }.max { $0.lastPathComponent < $1.lastPathComponent })
        let fixture = try await TransferWalkEquivalenceTests.Fixture.make()
        defer { fixture.cleanUp() }

        let live = fixture.router(mode: .off)
        let planner = JourneyPlanner(walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: live))
        let requests = try await planner.router(for: database).transferWalkingRequests()
        #expect(requests.count > 5_000)

        let dataset = try await live.prepareTransferWalkComputation()
        let result = try await TransferWalkTableBuilder(computer: live).build(
            requests: requests, dataset: dataset, reusing: nil, timetableIdentity: database.lastPathComponent, progress: { _, _ in })
        try fixture.store.write(result.data)
        print("TRANSFER_WALK_REAL_FEED pairs=\(result.pairs) negatives=\(result.negatives) bytes=\(result.data.count)")

        let offline = requests.map {
            OfflineWalkingRequest(from: LocalFirstWalkingRoutingProvider.walkingEndpoint($0.source),
                                  to: LocalFirstWalkingRoutingProvider.walkingEndpoint($0.destination))
        }
        let expected = await fixture.router(mode: .off).routes(offline, maximumConcurrency: 4)
        let stored = fixture.router(mode: .on)
        let served = await stored.routes(offline, maximumConcurrency: 4)
        #expect(served.count == expected.count)
        // The table's domain: every pair except the funicular interchange must be bit-identical.
        var tableDifferences = 0
        var funicularPairs: [Int] = []
        for index in expected.indices {
            if PafendallFunicularConnection.terminals(from: offline[index].from, to: offline[index].to) != nil {
                funicularPairs.append(index)
            } else if served[index] != expected[index] {
                tableDifferences += 1
            }
        }
        #expect(tableDifferences == 0)

        // Funicular pairs are never stored and are computed live on both sides. Their ride
        // length comes from `CLLocation.distance`, whose result shifts by a few centimetres
        // once native routing has run in the process (also without the table). Everything
        // else about them must still be identical.
        #expect(!funicularPairs.isEmpty)
        for index in funicularPairs {
            guard let left = expected[index], let right = served[index] else {
                #expect(expected[index] == nil && served[index] == nil)
                continue
            }
            #expect(left.duration == right.duration && left.source == right.source && left.coordinates == right.coordinates)
            #expect(abs(left.distanceMeters - right.distanceMeters) < 0.1)
            #expect(left.segments.count == right.segments.count)
            for (a, b) in zip(left.segments, right.segments) {
                #expect(a.mode == b.mode && a.name == b.name && a.originLabel == b.originLabel
                        && a.destinationLabel == b.destinationLabel && a.durationSeconds == b.durationSeconds
                        && a.polyline == b.polyline && abs(a.distanceMeters - b.distanceMeters) < 0.1)
            }
        }

        // Everything but the funicular pairs came from the table.
        let statistics = await stored.transferWalkStatistics()
        let funicular = offline.filter { PafendallFunicularConnection.terminals(from: $0.from, to: $0.to) != nil }.count
        #expect(statistics.hits + statistics.misses == Set(offline.map { TransferWalkKey(from: $0.from, to: $0.to) }).count)
        #expect(statistics.misses == funicular)
    }
}
