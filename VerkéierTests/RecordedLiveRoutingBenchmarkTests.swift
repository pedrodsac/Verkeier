import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

/// Opt-in Release benchmark against an already-installed feed. ATP is replayed
/// from the September 30 observation; regular tests never access live networking.
@Suite("Recorded live routing benchmark")
@MainActor
struct RecordedLiveRoutingBenchmarkTests {
    @Test func coldWarmAndRefreshOnInstalledLuxembourgFeed() async throws {
        guard ProcessInfo.processInfo.environment["ROUTING_LIVE_BENCHMARK"] == "1" else { return }
        let directory = MobiliteitGTFSService.installedDatabaseURL.deletingLastPathComponent()
        let service = MobiliteitGTFSService(directory: directory)
        let database = try #require(await service.routingDatabaseURL(), "Install a GTFS feed before benchmarking")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordedBoardProtocol.self]
        let client = MobiliteitAPIClient(apiKey: "fixture", baseURL: URL(string: "https://recorded-atp.invalid")!,
                                         session: URLSession(configuration: config))
        let planner = JourneyPlanner(realtimeClient: client)
        let anchor = ISO8601DateFormatter().date(from: "2026-09-30T18:35:00+02:00")!
        let started = ContinuousClock.now
        let router = try await planner.router(for: database)
        let snapshotTime = started.duration(to: .now)
        let query = RouteQuery(origin: .stop(id: "000220402034"), destination: .stop(id: "000400000095"),
                               departureTime: anchor, realtimePolicy: .bestEffort())
        let session = try await router.makeSession(for: query)
        let cold = try await session.initial()
        report("cold including snapshot", page: cold, elapsed: started.duration(to: .now), snapshot: snapshotTime)
        try validate(cold, anchor: anchor)

        let warmStarted = ContinuousClock.now
        let warmSession = try await router.makeSession(for: query)
        let warm = try await warmSession.initial()
        report("warm caches", page: warm, elapsed: warmStarted.duration(to: .now), snapshot: .zero)
        try validate(warm, anchor: anchor)
        #expect(warm.metrics.hafasRequests == 0)
        #expect(warm.metrics.hafasCacheHits > 0)

        let refreshStarted = ContinuousClock.now
        let refreshed = try await warmSession.refreshRealtime()
        report("forced refresh", page: refreshed, elapsed: refreshStarted.duration(to: .now), snapshot: .zero, previous: warm.metrics)
        try validate(refreshed, anchor: anchor)
        #expect(refreshed.metrics.hafasRequests > warm.metrics.hafasRequests)
        let staticStarted = ContinuousClock.now
        let staticSession = try await router.makeSession(for: .init(origin: query.origin,
            destination: query.destination, departureTime: anchor, preferences: query.preferences))
        let scheduled = try await staticSession.initial()
        report("schedule-only baseline", page: scheduled, elapsed: staticStarted.duration(to: .now), snapshot: .zero)
        #expect(!scheduled.journeys.isEmpty)
    }

    private func validate(_ page: JourneyPage, anchor: Date) throws {
        let rescued = try #require(page.journeys.first { journey in
            journey.legs.contains { leg in
                if case let .transit(transit) = leg { return transit.tripID == "24284828" }
                return false
            }
        }, "Recorded delayed bus must survive matching and RAPTOR")
        #expect(rescued.scheduledDeparture < anchor)
        #expect(rescued.effectiveDeparture >= anchor)
    }

    private func report(_ label: String, page: JourneyPage, elapsed: Duration, snapshot: Duration, previous: RoutingMetrics? = nil) {
        var m = page.metrics
        if let previous {
            m.hafasRequests -= previous.hafasRequests
            m.hafasCacheHits -= previous.hafasCacheHits
            m.realtimeResponseBytes -= previous.realtimeResponseBytes
            m.realtimePreparationMilliseconds -= previous.realtimePreparationMilliseconds
        }
        print("Recorded live benchmark \(label): \(elapsed); snapshot \(snapshot); HTTP \(m.hafasRequests); cache \(m.hafasCacheHits); bytes \(m.realtimeResponseBytes); stops \(m.realtimeBoardsCovered)/\(m.realtimeFrontierSize); predictions \(m.realtimePredictedEvents); coverage \(page.realtimeState); acquisition \(m.realtimePreparationMilliseconds)ms; RAPTOR \(m.raptorSearchMilliseconds)ms; build \(m.candidateBuildingMilliseconds)ms")
    }
}

private nonisolated final class RecordedBoardProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "recorded-atp.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let stop = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "id" }?.value
            let body: Data
            if stop == "000220402034" {
                guard let url = Bundle(for: Self.self).url(forResource: "esch-delayed-passlist", withExtension: "json")
                else { throw CocoaError(.fileNoSuchFile) }
                body = try Data(contentsOf: url)
            } else { body = Data("{\"Departure\":[]}".utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
