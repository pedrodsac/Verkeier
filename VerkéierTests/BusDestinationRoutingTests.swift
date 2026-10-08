import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

@Suite("Direct bus destination routing")
@MainActor
struct BusDestinationRoutingTests {
    @Test("The 321 stops at the destination instead of overshooting and walking back")
    func directDestinationPassesThroughPackageAdapter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("fixture.zip")
        let database = directory.appendingPathComponent("transit.sqlite")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\noperator,Operator,https://example.com,Europe/Berlin\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20260904,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nbus,operator,321,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon,wheelchair_boarding\norigin,Origin,49.6,6.1,1\ndestination,Destination,49.63,6.1,1\novershoot,Overshoot,49.629,6.1,1\n",
            "trips.txt": "route_id,service_id,trip_id,wheelchair_accessible\nbus,service,321,1\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n321,08:05:00,08:05:00,origin,1\n321,08:20:00,08:20:00,destination,2\n321,08:30:00,08:30:00,overshoot,3\n"
        ]
        for (path, content) in files {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate) { position, size in
                    data.subdata(in: Int(position)..<(Int(position) + size))
                }
        }
        _ = try await GTFSArchiveInstaller.install(archiveAt: archiveURL, databaseAt: database)
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-09-04T06:00:00Z"))
        let service = MobiliteitRouteService(databaseURL: database, walkingRouter: DestinationDetourWalkingRouter())
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1, transitStopID: "origin")
        let destination = LocationPoint(latitude: 49.63, longitude: 6.1, transitStopID: "destination")
        for page in [RouteSearchPage.initial, .laterAdjacent] {
            let result = try await service.calculateRoute(from: origin, to: destination,
                time: .departAt(anchor), filters: .init(), realtimeRefreshPolicy: .scheduleOnly, page: page)
            #expect(result.isAuthoritativeSnapshot)
            #expect(!result.options.isEmpty)
            #expect(result.options.allSatisfy {
                $0.transitLegs.count == 1 && $0.transitLegs.first?.routeName == "321"
                    && $0.arrivalTime == anchor.addingTimeInterval(20 * 60)
                    && $0.plan.legs.allSatisfy { $0.transportKind == .transit }
            })
        }
    }
}

private nonisolated struct DestinationDetourWalkingRouter: WalkingRouting {
    func estimates(from: LocationPoint, to destinations: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        var estimates: [OfflineWalkingEstimate] = []
        for destination in destinations {
            if let route = try? await route(from: from, to: destination.location) {
                estimates.append(.init(destinationID: destination.id, distanceMeters: route.distanceMeters,
                    duration: route.duration, source: .localOSM))
            }
        }
        return estimates
    }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        guard from.latitude == 49.629 && to.latitude == 49.63 else { throw WalkingRoutingError.noRoute }
        return .init(distanceMeters: 100, duration: 600,
            coordinates: [.init(latitude: from.latitude, longitude: from.longitude),
                          .init(latitude: to.latitude, longitude: to.longitude)], source: .localOSM)
    }
}
