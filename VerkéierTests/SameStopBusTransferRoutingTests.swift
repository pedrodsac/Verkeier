import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

@Suite("Same-stop bus transfer presentation")
@MainActor
struct SameStopBusTransferRoutingTests {
    @Test(arguments: [false, true])
    func luxexpoStyleTransferMatchesFilterAndKeepsWarning(avoidTightTransfers: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("fixture.zip")
        let database = directory.appendingPathComponent("transit.sqlite")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\noperator,Operator,https://example.com,Europe/Luxembourg\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20261008,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nfeeder,operator,322,3\ncity,operator,6,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon\na,Gromscheed,49.651650,6.230857\nx,Luxexpo,49.636375,6.174766\nd,Konrad Adenauer,49.629950,6.158028\n",
            "trips.txt": "route_id,service_id,trip_id\nfeeder,service,322\ncity,service,short\ncity,service,later\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n322,18:20:10,18:20:10,a,1\n322,18:30:05,18:30:05,x,2\nshort,18:32:40,18:32:40,x,1\nshort,18:39:10,18:39:10,d,2\nlater,18:47:50,18:47:50,x,1\nlater,18:54:20,18:54:20,d,2\n",
            "transfers.txt": "from_stop_id,to_stop_id,transfer_type,min_transfer_time\nx,x,2,450\n"
        ]
        for (path, content) in files {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        _ = try await GTFSArchiveInstaller.install(archiveAt: archiveURL, databaseAt: database)
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-10-08T18:11:00+02:00"))
        let service = MobiliteitRouteService(databaseURL: database, walkingRouter: SameStopOnlyWalkingRouter())
        let result = try await service.calculateRoute(
            from: .init(latitude: 49.651650, longitude: 6.230857, transitStopID: "a"),
            to: .init(latitude: 49.629950, longitude: 6.158028, transitStopID: "d"),
            time: .departAt(anchor), filters: .init(avoidTightTransfers: avoidTightTransfers),
            realtimeRefreshPolicy: .scheduleOnly, page: .initial)
        let short = result.options.first { $0.transitLegs.last?.tripId == "short" }
        #expect((short != nil) == !avoidTightTransfers)
        if let short {
            #expect(short.transitLegs.map(\.routeName) == ["322", "6"])
            #expect(short.transitLegs.last?.transferWarning == "Tight transfer")
            #expect(short.transitLegs.last?.requiredTotalTransferSeconds == 120)
            #expect(short.status(at: anchor) == .atRisk)
            #expect(short.arrivalTime == anchor.addingTimeInterval(28 * 60 + 10))
        }
        #expect(result.options.contains { $0.transitLegs.last?.tripId == "later" })
    }
}

private nonisolated struct SameStopOnlyWalkingRouter: WalkingRouting {
    func estimates(from: LocationPoint, to: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] { [] }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute { throw WalkingRoutingError.noRoute }
}
