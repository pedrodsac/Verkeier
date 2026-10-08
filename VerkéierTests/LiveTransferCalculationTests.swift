import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

@Suite("Live transfers in the initial route calculation")
@MainActor
struct LiveTransferCalculationTests {
    @Test(arguments: [false, true], [RouteRealtimeRefreshPolicy.useCache, .forceRefresh])
    func delayedAlternativeIsPresentBeforeAnyRefresh(arriveBy: Bool, refresh: RouteRealtimeRefreshPolicy) async throws {
        let fixture = try await TransferCalculationFixture()
        defer { fixture.remove() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferCalculationProtocol.self]
        let client = MobiliteitAPIClient(apiKey: "fixture",
            baseURL: URL(string: "https://initial-transfer-\(UUID()).invalid")!,
            session: URLSession(configuration: configuration))
        let service = MobiliteitRouteService(databaseURL: fixture.database,
            realtimeClient: client, walkingRouter: TransferCalculationWalkingRouter())
        let time: RoutePlanningTime = arriveBy
            ? .arriveBy(fixture.anchor.addingTimeInterval(70 * 60)) : .departAt(fixture.anchor)
        let scheduled = try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
            time: time, filters: .init(), realtimeRefreshPolicy: .scheduleOnly)
        #expect(!scheduled.options.isEmpty)
        #expect(scheduled.options.allSatisfy { !$0.transitLegs.contains { $0.tripId == "connection" } })

        let initial = try await service.calculateRoute(from: fixture.origin, to: fixture.destination,
            time: time, filters: .init(), realtimeRefreshPolicy: refresh)
        let rescued = try #require(initial.options.first {
            $0.transitLegs.map(\.tripId) == ["first", "connection"]
        })
        #expect(initial.isAuthoritativeSnapshot)
        #expect(initial.selectedOptionID == rescued.id)
        #expect(rescued.transitLegs.map(\.routeName) == ["10", "20"])
        #expect(rescued.transitLegs.allSatisfy {
            $0.departureTimingSource == .observed && $0.arrivalTimingSource == .observed
        })
        #expect(rescued.realtimeCoverage == .live)
        #expect(rescued.arrivalTime == fixture.anchor.addingTimeInterval(47 * 60))
        #expect(rescued.transitLegs[1].scheduledDepartureTime! < rescued.transitLegs[0].scheduledArrivalTime!)
        #expect(rescued.transitLegs[1].departureTime! > rescued.transitLegs[0].arrivalTime!)
    }
}

private struct TransferCalculationFixture {
    let directory: URL
    var database: URL { directory.appendingPathComponent("transit.sqlite") }
    let anchor = ISO8601DateFormatter().date(from: "2026-09-30T06:00:00Z")!
    var origin: LocationPoint { .init(latitude: 49.6, longitude: 6.1, transitStopID: "origin") }
    var destination: LocationPoint { .init(latitude: 49.7, longitude: 6.2, transitStopID: "destination") }

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent("fixture.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        let files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\noperator,Operator,https://example.com,Europe/Luxembourg\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20260930,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nbus,operator,10,3\nconnecting,operator,20,3\nslow,operator,30,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon\norigin,Origin,49.6,6.1\ntransfer,Transfer,49.65,6.15\ndestination,Destination,49.7,6.2\n",
            "trips.txt": "route_id,service_id,trip_id\nbus,service,first\nconnecting,service,connection\nslow,service,fallback\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nfirst,08:05:00,08:05:00,origin,1\nfirst,08:25:00,08:25:00,transfer,2\nconnection,08:20:00,08:20:00,transfer,1\nconnection,08:35:00,08:35:00,destination,2\nfallback,08:35:00,08:35:00,transfer,1\nfallback,09:00:00,09:00:00,destination,2\n"
        ]
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

/// Honors line filters, so requesting only the fallback cannot reveal line 20.
private nonisolated final class TransferCalculationProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasPrefix("initial-transfer-") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let stop = items.first { $0.name == "id" }?.value
        let lines = items.first { $0.name == "lines" }?.value?.split(separator: ",").map(String.init) ?? []
        let rows: [String]
        if stop == "origin" {
            rows = [Self.row(line: "10", trip: "first", from: "origin", to: "transfer",
                departure: "08:05:00", arrival: "08:25:00", liveDeparture: "08:12:00", liveArrival: "08:26:00")]
        } else if stop == "transfer" {
            var board: [String] = []
            if lines.isEmpty || lines.contains("20") {
                board.append(Self.row(line: "20", trip: "connection", from: "transfer", to: "destination",
                    departure: "08:20:00", arrival: "08:35:00", liveDeparture: "08:32:00", liveArrival: "08:47:00"))
            }
            if lines.isEmpty || lines.contains("30") {
                board.append(Self.row(line: "30", trip: "fallback", from: "transfer", to: "destination",
                    departure: "08:35:00", arrival: "09:00:00", liveDeparture: "08:35:00", liveArrival: "09:00:00"))
            }
            rows = board
        } else { rows = [] }
        let body = "{\"Departure\":[\(rows.joined(separator: ","))]}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func row(line: String, trip: String, from: String, to: String,
                            departure: String, arrival: String, liveDeparture: String, liveArrival: String) -> String {
        """
        {"JourneyDetailRef":{"ref":"\(trip)"},"Product":{"line":"\(line)","cls":"32"},
        "stopExtId":"\(from)","time":"\(departure)","date":"2026-09-30","rtTime":"\(liveDeparture)","rtDate":"2026-09-30",
        "Stops":{"Stop":[{"extId":"\(from)","depTime":"\(departure)","depDate":"2026-09-30",
        "rtDepTime":"\(liveDeparture)","rtDepDate":"2026-09-30"},
        {"extId":"\(to)","arrTime":"\(arrival)","arrDate":"2026-09-30",
        "rtArrTime":"\(liveArrival)","rtArrDate":"2026-09-30"}]}}
        """
    }
}

private nonisolated struct TransferCalculationWalkingRouter: WalkingRouting {
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
