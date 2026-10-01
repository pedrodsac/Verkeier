import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

@Suite("Journey planning package integration")
@MainActor
struct JourneyPlanningIntegrationTests {
    @Test("Measured walking feedback returns the package replacement snapshot")
    func refinementFeedbackPreservesNativeTransit() async throws {
        let fixture = try await JourneyIntegrationFixture()
        defer { fixture.remove() }
        let service = MobiliteitRouteService(databaseURL: fixture.database,
            walkingRouter: IntegrationWalkingRouter(), roadRouteProvider: IntegrationRoadProvider())
        let initial = try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .scheduleOnly)
        let original = try #require(initial.options.first)
        #expect(initial.isAuthoritativeSnapshot)
        #expect(original.journeySummary != nil)
        #expect(original.refinementToken != nil)
        #expect(original.plan.legs.first?.nativeWalkingRange == 0..<1)
        #expect(original.transitLegs.first?.mapCoordinates.count == 3)
        let originalTrip = try #require(original.transitLegs.first?.tripId)

        var snapshot: RouteCalculation?
        for await event in service.refinementEvents(in: [original], context: initial.validationContext) {
            if case let .calculation(result) = event { snapshot = result }
        }
        let updated = try #require(snapshot)
        #expect(updated.isAuthoritativeSnapshot)
        #expect(updated.invalidatedOptionIDs.contains(original.id))
        #expect(!updated.options.contains { $0.id == original.id })
        #expect(!updated.options.isEmpty)
        #expect(updated.selectedOptionID != original.id)
        #expect(updated.options.allSatisfy { ($0.departureTime ?? .distantPast) >= fixture.anchor })
        #expect(updated.options.allSatisfy { $0.transitLegs.first?.tripId != originalTrip })
        let replacement = try #require(updated.selectedOption)
        let access = try #require(replacement.plan.legs.first)
        let departure = try #require(access.departureTime)
        let arrival = try #require(access.arrivalTime)
        #expect(arrival.timeIntervalSince(departure) == 600)
        #expect(replacement.journeySummary?.walkingDuration == 600)
        #expect(replacement.transitLegs.first?.mapCoordinates.count == 3)

        // A new query supersedes the old refinement token, including through the app bridge.
        _ = try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .scheduleOnly)
        var staleSnapshots = 0
        for await event in service.refinementEvents(in: [original], context: initial.validationContext) {
            if case .calculation = event { staleSnapshots += 1 }
        }
        #expect(staleSnapshots == 0)
    }

    @Test("Passlist recovery reaches app timing evidence and explicit refresh")
    func liveRecoveryPreservesObservedArrival() async throws {
        let fixture = try await JourneyIntegrationFixture(); defer { fixture.remove() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IntegrationRealtimeProtocol.self]
        let client = MobiliteitAPIClient(apiKey: "fixture",
            baseURL: URL(string: "https://integration-live.invalid")!,
            session: URLSession(configuration: config))
        let service = MobiliteitRouteService(databaseURL: fixture.database,
            realtimeClient: client, walkingRouter: IntegrationWalkingRouter())
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1, transitStopID: "origin")
        let started = ContinuousClock.now
        let initial = try await service.calculateRoute(from: origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .forceRefresh)
        let leg = try #require(initial.selectedOption?.transitLegs.first)
        #expect(leg.tripId == "first")
        #expect(leg.departureTime == fixture.anchor.addingTimeInterval(12 * 60))
        #expect(leg.arrivalTime == fixture.anchor.addingTimeInterval(26 * 60))
        #expect(leg.departureTimingSource == .observed)
        #expect(leg.arrivalTimingSource == .observed)
        let cold = started.duration(to: .now)
        let warmStarted = ContinuousClock.now
        let refreshed = try await service.calculateRoute(from: origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .forceRefresh)
        #expect(refreshed.selectedOption?.transitLegs.first?.arrivalTime == leg.arrivalTime)
        print("Live fixture routing cold: \(cold); warm refresh: \(warmStarted.duration(to: .now))")
    }

    @Test("Every transit line retains live evidence through the app adapter")
    func transferLinesPreserveLiveStatus() async throws {
        let fixture = try await JourneyIntegrationFixture(withTransfer: true)
        defer { fixture.remove() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IntegrationRealtimeProtocol.self]
        let client = MobiliteitAPIClient(apiKey: "fixture",
            baseURL: URL(string: "https://integration-live-transfer.invalid")!,
            session: URLSession(configuration: config))
        let service = MobiliteitRouteService(databaseURL: fixture.database,
            realtimeClient: client, walkingRouter: IntegrationWalkingRouter())
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1, transitStopID: "origin")
        let result = try await service.calculateRoute(from: origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .forceRefresh)
        let option = try #require(result.selectedOption)
        #expect(option.transitLegs.map(\.routeName) == ["10", "20"])
        #expect(option.transitLegs.allSatisfy {
            $0.liveStatus == .delayed && $0.departureTimingSource == .observed && $0.arrivalTimingSource == .observed
        })
        #expect(option.realtimeCoverage == .live)
        #expect(option.arrivalTime == fixture.anchor.addingTimeInterval(47 * 60))
    }

    @Test("Faster direct walking remains the package recommendation in the app")
    func fasterWalkingRecommendationPassesThrough() async throws {
        let fixture = try await JourneyIntegrationFixture(withTransfer: true); defer { fixture.remove() }
        let service = MobiliteitRouteService(databaseURL: fixture.database, walkingRouter: DirectComparisonWalkingRouter())
        let result = try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
            time: .departAt(fixture.anchor), filters: .init(), realtimeRefreshPolicy: .scheduleOnly)
        let selected = try #require(result.selectedOption)
        #expect(selected.plan.legs.allSatisfy { $0.transportKind == .walking })
        #expect(selected.plan.expectedTravelTime == 900)
        #expect(result.isAuthoritativeSnapshot)
        #expect(result.options.contains { !$0.transitLegs.isEmpty })
    }

    @Test("Missing local graphs surface a typed walking-unavailable error")
    func missingGraphIsReported() async throws {
        let fixture = try await JourneyIntegrationFixture()
        defer { fixture.remove() }
        let service = MobiliteitRouteService(databaseURL: fixture.database)
        await #expect(throws: RoutingError.walkingUnavailable) {
            try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
                time: .departAt(fixture.anchor), filters: .init())
        }
    }
}

private struct JourneyIntegrationFixture {
    let directory: URL
    var database: URL { directory.appendingPathComponent("transit.sqlite") }
    let anchor = ISO8601DateFormatter().date(from: "2026-09-04T06:00:00Z")!
    var origin: LocationPoint { .init(latitude: 49.5999, longitude: 6.1) }
    var destination: LocationPoint { .init(latitude: 49.61, longitude: 6.1, transitStopID: "destination") }

    init(withTransfer: Bool = false) async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent("fixture.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        var files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\noperator,Operator,https://example.com,Europe/Berlin\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20260904,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nbus,operator,10,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon\norigin,Origin,49.6,6.1\ndestination,Destination,49.61,6.1\n",
            "shapes.txt": "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nshape,49.6,6.1,1\nshape,49.605,6.11,2\nshape,49.61,6.1,3\n",
            "trips.txt": "route_id,service_id,trip_id,shape_id\nbus,service,first,shape\nbus,service,second,shape\nbus,service,third,shape\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nfirst,08:05:00,08:05:00,origin,1\nfirst,08:25:00,08:25:00,destination,2\nsecond,08:10:00,08:10:00,origin,1\nsecond,08:30:00,08:30:00,destination,2\nthird,08:20:00,08:20:00,origin,1\nthird,08:40:00,08:40:00,destination,2\n"
        ]
        if withTransfer {
            files["routes.txt"]! += "connecting,operator,20,3\n"
            files["stops.txt"]! += "transfer,Transfer,49.605,6.1\n"
            files["trips.txt"] = "route_id,service_id,trip_id\nbus,service,first\nconnecting,service,connection\n"
            files["stop_times.txt"] = "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nfirst,08:05:00,08:05:00,origin,1\nfirst,08:25:00,08:25:00,transfer,2\nconnection,08:30:00,08:30:00,transfer,1\nconnection,08:45:00,08:45:00,destination,2\n"
        }
        for (path, content) in files {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate) { position, size in
                    data.subdata(in: Int(position)..<(Int(position) + size))
                }
        }
        _ = try await GTFSArchiveInstaller.install(archiveAt: zip, databaseAt: database)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private nonisolated struct IntegrationWalkingRouter: WalkingRouting {
    func estimates(from: LocationPoint, to destinations: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        destinations.map { .init(destinationID: $0.id, distanceMeters: 60, duration: 60, source: .localOSM) }
    }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        guard abs(from.latitude - to.latitude) < 0.002 else { throw WalkingRoutingError.noRoute }
        return .init(distanceMeters: 60, duration: 60,
            coordinates: [.init(latitude: from.latitude, longitude: from.longitude),
                          .init(latitude: to.latitude, longitude: to.longitude)], source: .localOSM)
    }
}

private nonisolated struct IntegrationRoadProvider: RoadRouteProviding {
    func roadRouteCoordinates(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> [RouteMapCoordinate]? {
        await roadRoute(from: from, to: to, transport: transport)?.coordinates
    }
    func roadRoute(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> RoadRoute? {
        .init(coordinates: [.init(latitude: from.latitude, longitude: from.longitude),
                            .init(latitude: to.latitude, longitude: to.longitude)],
              distanceMeters: 600, expectedTravelTime: 600)
    }
}

/// Fixed ATP response: no network or credentials are used by this integration test.
private nonisolated final class IntegrationRealtimeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ["integration-live.invalid", "integration-live-transfer.invalid"].contains(request.url?.host() ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = """
        {"Departure":[{"JourneyDetailRef":{"ref":"first"},"Product":{"line":"10","cls":"32"},
        "stopExtId":"origin","time":"08:05:00","date":"2026-09-04","rtTime":"08:12:00","rtDate":"2026-09-04",
        "Stops":{"Stop":[{"extId":"origin","depTime":"08:05:00","depDate":"2026-09-04",
        "rtDepTime":"08:12:00","rtDepDate":"2026-09-04"},
        {"extId":"destination","arrTime":"08:25:00","arrDate":"2026-09-04",
        "depTime":"08:25:00","depDate":"2026-09-04","rtArrTime":"08:26:00","rtArrDate":"2026-09-04",
        "rtDepTime":"08:26:00","rtDepDate":"2026-09-04"}]}}]}
        """
        if request.url?.host() == "integration-live-transfer.invalid" {
            let stop = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "id" }?.value
            if stop == "transfer" {
                body = """
                {"Departure":[{"JourneyDetailRef":{"ref":"connection"},"Product":{"line":"20","cls":"32"},
                "stopExtId":"transfer","time":"08:30:00","date":"2026-09-04","rtTime":"08:32:00","rtDate":"2026-09-04",
                "Stops":{"Stop":[{"extId":"transfer","depTime":"08:30:00","depDate":"2026-09-04",
                "rtDepTime":"08:32:00","rtDepDate":"2026-09-04"},
                {"extId":"destination","arrTime":"08:45:00","arrDate":"2026-09-04",
                "rtArrTime":"08:47:00","rtArrDate":"2026-09-04"}]}}]}
                """
            } else {
                body = body.replacingOccurrences(of: "destination", with: "transfer")
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private nonisolated struct DirectComparisonWalkingRouter: WalkingRouting {
    func estimates(from: LocationPoint, to destinations: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        destinations.map { .init(destinationID: $0.id, distanceMeters: 60, duration: 60, source: .localOSM) }
    }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        let duration: TimeInterval = abs(from.latitude - to.latitude) > 0.002 ? 900 : 60
        return .init(distanceMeters: duration, duration: duration,
            coordinates: [.init(latitude: from.latitude, longitude: from.longitude), .init(latitude: to.latitude, longitude: to.longitude)], source: .localOSM)
    }
}
