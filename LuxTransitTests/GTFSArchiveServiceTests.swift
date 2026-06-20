import Foundation
import Testing
import ZIPFoundation

@testable import LuxTransit

struct GTFSArchiveServiceTests {
    @Test func extractsRealZipArchive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "stop_id,stop_name\nS1,Hill Lift\n".write(
            to: source.appendingPathComponent("stops.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "route_id,route_short_name\nR1,15\n".write(
            to: nested.appendingPathComponent("routes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let archive = root.appendingPathComponent("gtfs.zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)

        let destination = root.appendingPathComponent("extracted", isDirectory: true)
        try GTFSArchiveService().unzip(archive, to: destination)

        let stops = try String(
            contentsOf: destination.appendingPathComponent("stops.txt"),
            encoding: .utf8
        )
        let routes = try String(
            contentsOf: destination.appendingPathComponent("nested/routes.txt"),
            encoding: .utf8
        )
        #expect(stops.contains("Hill Lift"))
        #expect(routes.contains("R1"))
    }

    @Test func rejectsInvalidZipArchive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let archive = root.appendingPathComponent("gtfs.zip")
        try Data("not a zip".utf8).write(to: archive)

        do {
            try GTFSArchiveService().unzip(
                archive,
                to: root.appendingPathComponent("extracted", isDirectory: true)
            )
            Issue.record("Expected invalid archive error.")
        } catch GTFSUpdateError.invalidArchive {
        } catch {
            Issue.record("Expected invalid archive error, got \(error).")
        }
    }
}
