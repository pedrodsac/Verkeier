import Foundation
import ZIPFoundation

nonisolated protocol GTFSArchiveExtracting: Sendable {
    func unzip(_ archiveURL: URL, to destination: URL) throws
}

nonisolated struct GTFSArchiveService: GTFSArchiveExtracting {
    func unzip(_ archiveURL: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            try fileManager.unzipItem(at: archiveURL, to: destination)
        } catch {
            throw GTFSUpdateError.invalidArchive
        }

        let extractedEntries = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        )
        guard !extractedEntries.isEmpty else {
            throw GTFSUpdateError.invalidArchive
        }
    }
}
