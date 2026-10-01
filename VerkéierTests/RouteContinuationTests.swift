import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

@Suite("Verified stay-aboard presentation")
@MainActor
struct RouteContinuationTests {
    private func option(continues: Bool) -> RouteOption {
        let a = LocationPoint(name: "A", latitude: 49.6, longitude: 6.1, transitStopID: "a")
        let b = LocationPoint(name: "B", latitude: 49.61, longitude: 6.1, transitStopID: "b")
        let d = LocationPoint(name: "D", latitude: 49.62, longitude: 6.1, transitStopID: "d")
        let start = Date(timeIntervalSince1970: 100_000)
        let first = RoutePlan.Leg(id: "first", mode: .bus, transportKind: .transit, routeName: "16", tripId: "first",
            originStopId: "a", destinationStopId: "b", origin: a, destination: b,
            departureTime: start, arrivalTime: start.addingTimeInterval(600))
        var second = RoutePlan.Leg(id: "second", mode: .bus, transportKind: .transit, routeName: "18", tripId: "second",
            originStopId: "b", destinationStopId: "d", origin: b, destination: d,
            departureTime: start.addingTimeInterval(600), arrivalTime: start.addingTimeInterval(1200))
        if continues { second.continuesInSeatFromTripID = "first" }
        return .init(id: "route", plan: .init(id: "route", origin: a, destination: d, expectedTravelTime: 1200,
            distanceMeters: 0, legs: [first, second], dataSource: .local), mapOverlay: nil)
    }

    @Test func timelineShareAndAccessibilitySayStayAboard() throws {
        let route = option(continues: true)
        let boundary = try #require(RouteTimelineBuilder.items(from: route.plan.legs).compactMap {
            if case let .place(node) = $0, node.id == "place-1" { node } else { nil }
        }.first)
        #expect(boundary.role == .stayAboard)
        #expect(boundary.platform == nil && boundary.transferWarning == nil && boundary.waitMinutes == nil)
        #expect(boundary.stayAboardAccessibilityLabel == "Stay aboard at B.")
        let text = route.shareText(originTitle: "A", destinationTitle: "D")
        #expect(text.contains("Stay aboard at B"))
        #expect(text.contains("0 transfers"))
        #expect(text.contains("16") && text.contains("18"))
        #expect(route.transferCount == 0 && route.transferGapDurations == [])
        #expect(RouteItineraryValidator.assess(route, context: .init(anchor: Date(timeIntervalSince1970: 100_000), arriveBy: false, minimumTransferSeconds: 120)) == .feasible(minimumTransferSlack: nil))
    }

    @Test func packageContinuationMapsToAppWithoutLostBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = directory.appendingPathComponent("fixture.zip")
        let database = directory.appendingPathComponent("feed.sqlite")
        let archive = try Archive(url: zip, accessMode: .create)
        let files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\nop,Operator,https://example.com,Europe/Luxembourg\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20260904,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nr1,op,16,3\nr2,op,18,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon\na,A,49.6,6.1\nb,B,49.61,6.1\nd,D,49.62,6.1\n",
            "trips.txt": "route_id,service_id,trip_id\nr1,service,first\nr2,service,second\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nfirst,08:00:00,08:00:00,a,1\nfirst,08:10:00,08:10:00,b,2\nsecond,08:10:00,08:10:00,b,1\nsecond,08:20:00,08:20:00,d,2\n",
            "transfers.txt": "from_trip_id,to_trip_id,transfer_type\nfirst,second,4\n"
        ]
        for (path, content) in files {
            let bytes = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        _ = try await GTFSArchiveInstaller.install(archiveAt: zip, databaseAt: database, generation: 7)
        let engine = JourneyPlanner()
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-09-04T06:00:00Z"))
        let session = try await engine.makePlanningSession(databaseURL: database,
            request: .init(origin: .stop(id: "a"), destination: .stop(id: "d"), time: .departAt(anchor), preferences: .init(maxTransfers: 0)))
        let result = try await session.calculate(refresh: .scheduleOnly)
        let a = LocationPoint(name: "A", latitude: 49.6, longitude: 6.1, transitStopID: "a")
        let d = LocationPoint(name: "D", latitude: 49.62, longitude: 6.1, transitStopID: "d")
        let service = MobiliteitRouteService(databaseURL: database, engine: engine)
        let calculation = service.calculation(from: result, origin: a, destination: d)
        let mapped = try #require(calculation.options.first)
        #expect(calculation.isAuthoritativeSnapshot)
        #expect(mapped.plan.legs.count == 2 && mapped.transferCount == 0)
        #expect(mapped.plan.legs.last?.continuesInSeatFromTripID == "first")
        #expect(mapped.plan.legs.first?.transitInstanceKey == "g7:first@20260904")
        #expect(mapped.plan.legs.first?.boardingStopSequence == 1)
        #expect(mapped.shareText(originTitle: "A", destinationTitle: "D").contains("Stay aboard"))
    }

    @Test func ordinaryChangeStillRequiresTransferMinimum() {
        let route = option(continues: false)
        #expect(RouteTimelineBuilder.items(from: route.plan.legs).contains { if case let .place(node) = $0 { node.role == .transfer } else { false } })
        #expect(route.transferCount == 1)
        #expect(RouteItineraryValidator.assess(route, context: .init(anchor: Date(timeIntervalSince1970: 100_000), arriveBy: false, minimumTransferSeconds: 120)) == .invalid(.missedTransfer))
    }

    @Test func unverifiedPersistedContinuationCannotBypassMinimum() {
        let valid = option(continues: true)
        var legs = valid.plan.legs
        legs[1].continuesInSeatFromTripID = "unrelated-trip"
        let invalid = valid.replacingLegs(legs)
        #expect(RouteItineraryValidator.assess(invalid, context: .init(anchor: Date(timeIntervalSince1970: 100_000), arriveBy: false, minimumTransferSeconds: 120)) == .invalid(.invalidContinuation))
    }

    @Test func continuationMetadataSurvivesPersistenceAndGeometryReplacement() throws {
        let route = option(continues: true)
        let decoded = try JSONDecoder().decode(RouteOption.self, from: JSONEncoder().encode(route))
        #expect(decoded.plan.legs.last?.continuesInSeatFromTripID == "first")
        let replaced = route.replacingLegs(of: .transit, from: decoded)
        #expect(replaced.transferCount == 0)
        #expect(replaced.plan.legs.last?.continuesInSeatFromTripID == "first")
    }
}
