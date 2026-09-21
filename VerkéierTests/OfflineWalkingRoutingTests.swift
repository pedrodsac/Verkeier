import CryptoKit
import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Offline walking routing")
struct OfflineWalkingRoutingTests {
    @Test("Nearby prefilter caps candidates and excludes distant stops")
    func nearbyPrefilterLimitsAndFilters() {
        let origin = LocationPoint(latitude: 49.6116, longitude: 6.1319)
        let stops = [
            stop(id: "near", latitude: 49.6120, longitude: 6.1325),
            stop(id: "middle", latitude: 49.6200, longitude: 6.1325),
            stop(id: "far", latitude: 49.7000, longitude: 6.1325),
        ]

        let candidates = NearbyStopPrefilter(
            candidateLimit: 2,
            maximumStraightLineDistanceMeters: 2_000
        ).destinations(from: stops, origin: origin)

        #expect(candidates.map(\.id) == ["near", "middle"])
    }

    @Test("A bad staged download leaves the active dataset untouched")
    func failedInstallPreservesActiveDataset() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineWalkingRoutingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let archive = folder.appendingPathComponent("first.tar")
        let contents = Data("valid graph fixture".utf8)
        try contents.write(to: archive)
        let manager = RoutingDatasetManager(rootURL: folder, appBuild: 10)
        let firstManifest = manifest(version: "v1", archive: contents, url: archive)
        _ = try await manager.install(
            archiveURL: archive,
            manifest: firstManifest,
            validator: AcceptingDatasetValidator()
        )

        let badArchive = folder.appendingPathComponent("bad.tar")
        let badContents = Data("corrupt graph fixture".utf8)
        try badContents.write(to: badArchive)
        var badManifest = manifest(version: "v2", archive: badContents, url: badArchive)
        badManifest = RoutingDatasetManifest(
            schemaVersion: badManifest.schemaVersion,
            region: badManifest.region,
            datasetVersion: badManifest.datasetVersion,
            routingEngine: badManifest.routingEngine,
            artifact: .init(
                url: badManifest.artifact.url,
                sizeBytes: badManifest.artifact.sizeBytes,
                sha256: String(repeating: "0", count: 64)
            ),
            minimumAppBuild: badManifest.minimumAppBuild
        )

        do {
            _ = try await manager.install(
                archiveURL: badArchive,
                manifest: badManifest,
                validator: AcceptingDatasetValidator()
            )
            Issue.record("Expected the bad archive to fail checksum validation")
        } catch let error as RoutingDatasetError {
            #expect(error == .checksumMismatch)
        } catch {
            Issue.record("Unexpected installation error: \(error)")
        }
        let active = try await manager.activeDataset()
        #expect(active?.version == "v1")
    }

    @Test("A six-digit Valhalla shape decodes to MapKit coordinates")
    func decodesPolyline6() throws {
        // (0, 0) → (1, 1), encoded with six decimal digits of precision.
        let coordinates = try ValhallaWalkingRouter.decodePolyline6("??_c`|@_c`|@")
        #expect(coordinates.count == 2)
        #expect(abs(coordinates[0].latitude) < 0.000001)
        #expect(abs(coordinates[1].longitude - 1) < 0.000001)
    }

    @Test("Transit search receives the local walk distance and duration")
    func transitWalkingProviderUsesLocalRoute() async throws {
        let provider = LocalFirstWalkingRoutingProvider(
            walkingRouter: FixedOfflineWalkingRouter()
        )
        let route = try await provider.route(.init(
            source: .init(latitude: 49.61, longitude: 6.12),
            destination: .init(latitude: 49.62, longitude: 6.13)
        ))

        #expect(route.durationSeconds == 777)
        #expect(route.distanceMeters == 1_234)
        #expect(route.polyline.count == 3)
    }

    private func stop(id: String, latitude: Double, longitude: Double) -> Stop {
        Stop(
            id: id,
            name: id,
            location: LocationPoint(latitude: latitude, longitude: longitude),
            modes: [.bus],
            dataSource: .mock
        )
    }

    private func manifest(version: String, archive: Data, url: URL) -> RoutingDatasetManifest {
        RoutingDatasetManifest(
            schemaVersion: 1,
            region: "luxembourg",
            datasetVersion: version,
            routingEngine: .init(
                valhallaMobileVersion: RoutingDatasetManager.valhallaMobileVersion,
                valhallaCoreCommit: "fixture"
            ),
            artifact: .init(
                url: url,
                sizeBytes: Int64(archive.count),
                sha256: SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
            ),
            minimumAppBuild: 10
        )
    }
}

private struct AcceptingDatasetValidator: RoutingDatasetValidating {
    func validate(_ dataset: RoutingDataset) async throws {
        #expect(FileManager.default.fileExists(atPath: dataset.tileArchiveURL.path))
    }
}

private nonisolated struct FixedOfflineWalkingRouter: WalkingRouting {
    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        destinations.map {
            .init(
                destinationID: $0.id,
                distanceMeters: 1_234,
                duration: 777,
                source: .localOSM
            )
        }
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        .init(
            distanceMeters: 1_234,
            duration: 777,
            coordinates: [
                .init(origin),
                .init(latitude: 49.615, longitude: 6.125),
                .init(destination),
            ],
            source: .localOSM
        )
    }
}
