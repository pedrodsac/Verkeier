import Foundation
import Testing

@testable import LuxTransit

struct GTFSUpdateServiceTests {
    @Test func successfulUpdateCommitsSearchableGTFSIndex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GTFSLocalStore(rootDirectory: root)
        let service = GTFSUpdateService(
            metadataClient: MockGTFSMetadataClient(resource: remoteResource(id: "resource-1")),
            downloadService: MockGTFSDownloadService(),
            archiveService: MockGTFSArchiveService(),
            store: store,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = await service.checkForUpdates(
            force: true, now: Date(timeIntervalSince1970: 1_000))

        #expect(snapshot.status == .updated)
        #expect(snapshot.metadata?.resourceId == "resource-1")
        #expect(FileManager.default.fileExists(atPath: store.currentDirectory.path))
        #expect(FileManager.default.fileExists(atPath: store.stopsIndexURL.path))

        let gtfsService = LocalGTFSService(store: store)
        let lift = try #require(gtfsService.searchStops(query: "lift").first)
        #expect(lift.name == "Hill Lift")
        #expect(lift.modes == [.funicular])
        #expect(gtfsService.routesForStop(id: lift.id).contains { $0.shortName == "F1" })
    }

    @Test func failedUpdateKeepsExistingGTFS() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GTFSLocalStore(rootDirectory: root)
        let initialFeed = try makeGTFSFeedDirectory(stopName: "Stable Stop")
        let initialIndex = root.appendingPathComponent("initial-index.json")
        try GTFSIndexBuilder().buildStopsIndex(from: initialFeed, to: initialIndex)
        let initialMetadata = LocalGTFSMetadata(
            resourceId: "old",
            title: "Old GTFS",
            checksum: "old-checksum",
            lastModified: nil,
            downloadedAt: Date(timeIntervalSince1970: 10),
            indexedAt: Date(timeIntervalSince1970: 10)
        )
        try store.commit(
            feedDirectory: initialFeed, indexURL: initialIndex, metadata: initialMetadata)

        let service = GTFSUpdateService(
            metadataClient: MockGTFSMetadataClient(resource: remoteResource(id: "new")),
            downloadService: MockGTFSDownloadService(),
            archiveService: FailingGTFSArchiveService(),
            store: store,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = await service.checkForUpdates(
            force: true, now: Date(timeIntervalSince1970: 2_000))

        #expect(snapshot.status == .failed)
        #expect((try store.loadMetadata())?.resourceId == "old")
        let gtfsService = LocalGTFSService(store: store)
        #expect(gtfsService.searchStops(query: "stable").first?.name == "Stable Stop")
    }

    private func remoteResource(id: String) -> DataPublicResource {
        DataPublicResource(
            id: id,
            title: "gtfs.zip",
            latest: "https://example.com/gtfs.zip",
            url: nil,
            filetype: "zip",
            mime: "application/zip",
            checksum: DataPublicChecksum(type: "sha256", value: "\(id)-checksum"),
            lastModified: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private struct MockGTFSMetadataClient: GTFSMetadataFetching {
    let resource: DataPublicResource

    func fetchDataset() async throws -> DataPublicDataset {
        DataPublicDataset(resources: [resource])
    }
}

private struct MockGTFSDownloadService: GTFSDownloading {
    func download(from url: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mock zip".utf8).write(to: destination)
    }
}

private struct MockGTFSArchiveService: GTFSArchiveExtracting {
    func unzip(_ archiveURL: URL, to destination: URL) throws {
        let feed = try makeGTFSFeedDirectory(stopName: "Hill Lift")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: feed, to: destination)
    }
}

private struct FailingGTFSArchiveService: GTFSArchiveExtracting {
    func unzip(_ archiveURL: URL, to destination: URL) throws {
        throw GTFSUpdateError.invalidArchive
    }
}

private func makeGTFSFeedDirectory(stopName: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let files = [
        "agency.txt": """
        agency_id,agency_name,agency_url,agency_timezone
        Operator,Operator,https://example.com,Europe/Luxembourg
        """,
        "stops.txt": """
        stop_id,stop_name,stop_lat,stop_lon,zone_id,location_type
        S1,\(stopName),49.6289,6.21474,Findel,
        """,
        "routes.txt": """
        route_id,agency_id,route_short_name,route_long_name,route_type
        F1,Operator,F1,Lower Station - Upper Station,7
        """,
        "trips.txt": """
        route_id,service_id,trip_id
        F1,WEEK,T-F1
        """,
        "stop_times.txt": """
        trip_id,arrival_time,departure_time,stop_id,stop_sequence
        T-F1,08:00:00,08:00:00,S1,1
        """,
        "calendar_dates.txt": """
        service_id,date,exception_type
        WEEK,20260614,1
        """,
    ]

    for (fileName, content) in files {
        try (content + "\n").write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    return directory
}
