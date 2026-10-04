import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

/// Opt-in replay against an installed feed and the app's real pedestrian graph.
/// No network; the origin is the existing Gromscheed address regression point.
@Suite struct RoutingScreenshotReplayTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROUTING_SCREENSHOT_REPLAY_DATABASE"] != nil), arguments: [false, true])
    func morningLuxexpoConnectionAvoidsRedundant325(earlier322Arrival: Bool) async throws {
        let environment = ProcessInfo.processInfo.environment
        let database = URL(fileURLWithPath: try #require(environment["ROUTING_SCREENSHOT_REPLAY_DATABASE"]))
        let tiles = URL(fileURLWithPath: try #require(environment["ROUTING_SCREENSHOT_REPLAY_TILES"]))
        let pedestrian = try ValhallaWalkingRouter(tileArchiveURL: tiles, datasetVersion: "morning-screenshot-replay")
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-10-04T11:16:00+02:00"))
        // The installed schedule misses the 11:29:20 tram by seven seconds.
        // This controlled live fixture moves only the 322 arrival 20 seconds earlier.
        let prediction = try #require(ISO8601DateFormatter().date(from: "2026-10-04T11:26:50+02:00"))
        let realtime = MorningLuxexpoRealtimeFixture(patch: .init(tripID: "24262729",
            serviceDate: try GTFSDate(parsing: "20261004"), events: [.init(stopID: "000200417050",
                effectiveArrival: prediction, arrivalSource: .reported, stopSequence: 19, observedAt: anchor)]))
        let router = try await TransitRouter(databaseURL: database,
            walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: pedestrian),
            realtimeProvider: earlier322Arrival ? realtime : nil, clock: { anchor })
        let query = RouteQuery(origin: .stop(id: "000200508004"),
            destination: .stop(id: "000200417031"), departureTime: anchor,
            realtimePolicy: earlier322Arrival ? .bestEffort() : .disabled)
        let session = try await router.makeSession(for: query)
        let page = try await session.initial(count: 100, searchHorizon: 60 * 60)
        let morning = page.journeys.filter { $0.effectiveArrival < anchor.addingTimeInterval(60 * 60) }
        func rides(_ journey: Journey) -> [TransitLeg] {
            journey.legs.compactMap { if case let .transit(ride) = $0 { ride } else { nil } }
        }
        for journey in morning {
            print("MORNING_SCREENSHOT_REPLAY earlier322=\(earlier322Arrival) depart=\(journey.effectiveDeparture) arrive=\(journey.effectiveArrival) walk=\(Int(journey.walkingDuration)) rides=\(rides(journey).map { "\($0.route.shortName ?? "?"):\($0.tripID):\($0.board.stop.name)->\($0.alight.stop.name)" })")
        }
        #expect(!morning.isEmpty)
        #expect(morning.allSatisfy { !JourneyPublicationValidator.assess($0, query: query).isInvalid })
        #expect(morning.contains { rides($0).map { $0.route.shortName ?? "" } == ["322", "325", "T1"] } == !earlier322Arrival)
        #expect(morning.contains { rides($0).map { $0.route.shortName ?? "" } == ["322", "T1"] })
        let earlyTram = morning.filter { rides($0).last?.tripID == "24320542" }
        #expect(!earlyTram.isEmpty)
        #expect(earlyTram.allSatisfy { rides($0).map { $0.route.shortName ?? "" } ==
            (earlier322Arrival ? ["322", "T1"] : ["322", "325", "T1"]) })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROUTING_SCREENSHOT_REPLAY_DATABASE"] != nil))
    func eveningConnectionsAvoidRedundant326() async throws {
        let environment = ProcessInfo.processInfo.environment
        let database = URL(fileURLWithPath: try #require(environment["ROUTING_SCREENSHOT_REPLAY_DATABASE"]))
        let tiles = URL(fileURLWithPath: try #require(environment["ROUTING_SCREENSHOT_REPLAY_TILES"]))
        let pedestrian = try ValhallaWalkingRouter(tileArchiveURL: tiles, datasetVersion: "screenshot-replay")
        let walking = LocalFirstWalkingRoutingProvider(walkingRouter: pedestrian)
        let router = try await TransitRouter(databaseURL: database, walkingProvider: walking)
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-10-01T20:18:00+02:00"))
        let origin = Coordinate(latitude: 49.6541071, longitude: 6.2296443)
        let query = RouteQuery(origin: .coordinate(origin, label: "Gromscheed address"),
            destination: .stop(id: "000200417019"), departureTime: anchor, realtimePolicy: .disabled)
        let session = try await router.makeSession(for: query)
        let page = try await session.boundedPage(count: 100)
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg"); formatter.dateFormat = "HH:mm:ss"
        func rides(_ journey: Journey) -> [TransitLeg] {
            journey.legs.compactMap { if case let .transit(ride) = $0 { ride } else { nil } }
        }
        let directSession = try await router.makeSession(for: .init(origin: .stop(id: "000200508004"),
            destination: .stop(id: "000200417050"), departureTime: anchor.addingTimeInterval(13 * 60),
            preferences: .init(maxTransfers: 0), realtimePolicy: .disabled))
        let direct = try await directSession.initial(count: 20, searchHorizon: 30 * 60)
        #expect(direct.journeys.contains { journey in
            let actions = rides(journey)
            return actions.count == 1 && actions.first?.tripID == "24264856"
                && actions.first?.alight.stop.name == "Kirchberg, Gare routière Luxexpo"
        })
        let evening = page.journeys.filter { $0.effectiveArrival < anchor.addingTimeInterval(60 * 60) }
        for journey in evening {
            print("SCREENSHOT_REPLAY depart=\(formatter.string(from: journey.effectiveDeparture)) arrive=\(formatter.string(from: journey.effectiveArrival)) walk=\(Int(journey.walkingDuration)) rides=\(rides(journey).map { "\($0.route.shortName ?? "?"):\($0.tripID):\($0.board.stop.name)->\($0.alight.stop.name)" })")
        }
        #expect(!evening.isEmpty)
        #expect(evening.allSatisfy { !JourneyPublicationValidator.assess($0, query: query).isInvalid })
        #expect(!evening.contains { rides($0).map { $0.route.shortName ?? "" } == ["326", "311", "18"] })
        #expect(!evening.contains { rides($0).map { $0.route.shortName ?? "" } == ["326", "850", "16"] })
        #expect(evening.contains { journey in
            let actions = rides(journey)
            return actions.map { $0.route.shortName ?? "" } == ["850", "16"]
                && actions.first?.board.stop.name == "Senningerberg, Charlys Statioun"
        })
    }
}

private struct MorningLuxexpoRealtimeFixture: RealtimeRoutingProvider {
    let patch: RealtimeTripPatch
    func patches(for stopIDs: [String], from: Date, through: Date, refreshPolicy: RealtimeRefreshPolicy) async throws -> RealtimePatchBatch {
        .init(patches: [patch], requestedStopIDs: Set(stopIDs), coveredStopIDs: Set(stopIDs))
    }
}
