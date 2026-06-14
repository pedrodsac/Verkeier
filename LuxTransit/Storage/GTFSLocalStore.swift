import Foundation

nonisolated struct GTFSLocalStore: Sendable {
    let rootDirectory: URL

    init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("GTFS", isDirectory: true)
    ) {
        self.rootDirectory = rootDirectory
    }

    var currentDirectory: URL {
        rootDirectory.appendingPathComponent("current", isDirectory: true)
    }

    var indexesDirectory: URL {
        rootDirectory.appendingPathComponent("indexes", isDirectory: true)
    }

    var stopsIndexURL: URL {
        indexesDirectory.appendingPathComponent("stops-index.json")
    }

    private var metadataURL: URL {
        rootDirectory.appendingPathComponent("metadata.json")
    }

    private var stateURL: URL {
        rootDirectory.appendingPathComponent("state.json")
    }

    func bootstrap() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: indexesDirectory, withIntermediateDirectories: true)
    }

    func loadMetadata() throws -> LocalGTFSMetadata? {
        try decodeIfExists(LocalGTFSMetadata.self, from: metadataURL)
    }

    func saveMetadata(_ metadata: LocalGTFSMetadata) throws {
        try bootstrap()
        try encode(metadata, to: metadataURL)
    }

    func loadLastMetadataCheckAt() throws -> Date? {
        try decodeIfExists(GTFSLocalState.self, from: stateURL)?.lastMetadataCheckAt
    }

    func saveLastMetadataCheckAt(_ date: Date) throws {
        try bootstrap()
        try encode(GTFSLocalState(lastMetadataCheckAt: date), to: stateURL)
    }

    func hasCurrentFeed() -> Bool {
        FileManager.default.fileExists(atPath: currentDirectory.path)
    }

    func resetTempDirectory() throws -> URL {
        let tempRoot = rootDirectory.appendingPathComponent("temp", isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: tempRoot.path) {
            try fileManager.removeItem(at: tempRoot)
        }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    func cleanTempDirectory() {
        let tempRoot = rootDirectory.appendingPathComponent("temp", isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func commit(
        feedDirectory: URL,
        indexURL: URL,
        metadata: LocalGTFSMetadata
    ) throws {
        try bootstrap()
        let fileManager = FileManager.default
        let replacementCurrent = rootDirectory.appendingPathComponent(
            "current.replacement",
            isDirectory: true
        )
        let replacementIndex = rootDirectory.appendingPathComponent("stops-index.replacement.json")
        let backupCurrent = rootDirectory.appendingPathComponent("current.backup", isDirectory: true)
        let backupIndex = rootDirectory.appendingPathComponent("stops-index.backup.json")

        for url in [replacementCurrent, replacementIndex, backupCurrent, backupIndex] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        try fileManager.copyItem(at: feedDirectory, to: replacementCurrent)
        try fileManager.copyItem(at: indexURL, to: replacementIndex)

        if fileManager.fileExists(atPath: currentDirectory.path) {
            try fileManager.moveItem(at: currentDirectory, to: backupCurrent)
        }

        do {
            try fileManager.moveItem(at: replacementCurrent, to: currentDirectory)
            try fileManager.createDirectory(at: indexesDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: stopsIndexURL.path) {
                try fileManager.moveItem(at: stopsIndexURL, to: backupIndex)
            }
            try fileManager.moveItem(at: replacementIndex, to: stopsIndexURL)
            try saveMetadata(metadata)
            try? fileManager.removeItem(at: backupCurrent)
            try? fileManager.removeItem(at: backupIndex)
        } catch {
            if fileManager.fileExists(atPath: currentDirectory.path) {
                try? fileManager.removeItem(at: currentDirectory)
            }
            if fileManager.fileExists(atPath: backupCurrent.path) {
                try? fileManager.moveItem(at: backupCurrent, to: currentDirectory)
            }
            if fileManager.fileExists(atPath: stopsIndexURL.path) {
                try? fileManager.removeItem(at: stopsIndexURL)
            }
            if fileManager.fileExists(atPath: backupIndex.path) {
                try? fileManager.moveItem(at: backupIndex, to: stopsIndexURL)
            }
            throw error
        }
    }

    private func decodeIfExists<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.gtfsLocal.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.gtfsLocal.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

nonisolated private struct GTFSLocalState: Codable {
    let lastMetadataCheckAt: Date?
}

extension JSONEncoder {
    nonisolated static var gtfsLocal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var gtfsLocal: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
