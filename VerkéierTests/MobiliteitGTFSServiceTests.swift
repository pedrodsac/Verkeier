import Foundation
import MobiliteitKit
import Testing
import ZIPFoundation
@testable import Verkeier

struct MobiliteitGTFSServiceTests {
    @Test func constructionDefersDirectoryCreationUntilActorAccess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = MobiliteitGTFSService(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await service.feedStatus() == .unavailable)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(await service.routingDatabaseURL() == nil)
    }

    @Test func firstOfflineQueryLoadsInstalledGenerationAndPreservesActiveDatabase() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let active = directory.appendingPathComponent("gtfs-generation-active.sqlite")
        let obsolete = directory.appendingPathComponent("gtfs-generation-old.sqlite")
        try Data().write(to: obsolete)
        let service = MobiliteitGTFSService(directory: directory)
        // Resources are deliberately installed after construction, before the
        // first actor call. Init must neither read metadata nor delete files.
        #expect(FileManager.default.fileExists(atPath: obsolete.path))
        try await installFixture(in: directory, database: active)
        let metadata = InstalledMetadata(databaseFilename: active.lastPathComponent)
        try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("metadata.json"))

        let results = await service.searchStops(query: "Central")
        #expect(results.map(\.id) == ["a"])
        #expect(await service.routingDatabaseURL() == active)
        let status = await service.feedStatus()
        #expect(status.isReady)
        #expect(status.resourceTitle == "Fixture timetable")
        #expect(!FileManager.default.fileExists(atPath: obsolete.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(await service.searchStops(query: "Central") == results)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GTFSService-\(UUID().uuidString)")
    }

    private func installFixture(in directory: URL, database: URL) async throws {
        let zip = directory.appendingPathComponent("fixture.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        let files = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\nop,Operator,https://example.com,Europe/Luxembourg\n",
            "calendar_dates.txt": "service_id,date,exception_type\nservice,20990101,1\n",
            "routes.txt": "route_id,agency_id,route_short_name,route_type\nr,op,1,3\n",
            "stops.txt": "stop_id,stop_name,stop_lat,stop_lon\na,Central,49.6,6.1\nb,Gare,49.61,6.1\n",
            "trips.txt": "route_id,service_id,trip_id\nr,service,trip\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\ntrip,08:00:00,08:00:00,a,1\ntrip,08:10:00,08:10:00,b,2\n"
        ]
        for (path, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        _ = try await GTFSArchiveInstaller.install(archiveAt: zip, databaseAt: database, generation: 1)
    }

    private struct InstalledMetadata: Encodable {
        let resourceID = "fixture"
        let resourceTitle = "Fixture timetable"
        let downloadedAt = Date.now
        let lastCheckedAt = Date.now
        let generation = 1
        let validThrough = "2099-01-01"
        let databaseFilename: String
    }
}
