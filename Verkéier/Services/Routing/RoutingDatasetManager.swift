import CryptoKit
import Foundation

/// Metadata published beside an immutable Valhalla tile archive.
nonisolated struct RoutingDatasetManifest: Codable, Hashable, Sendable {
    struct RoutingEngine: Codable, Hashable, Sendable {
        let valhallaMobileVersion: String
        let valhallaCoreCommit: String
    }

    struct Artifact: Codable, Hashable, Sendable {
        let url: URL
        let sizeBytes: Int64
        let sha256: String
    }

    let schemaVersion: Int
    let region: String
    let datasetVersion: String
    let osmTimestamp: Date?
    let routingEngine: RoutingEngine
    let artifact: Artifact
    let minimumAppBuild: Int
    let createdAt: Date?
    let source: String?
    let formatVersion: Int?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, region, datasetVersion, osmTimestamp, routingEngine
        case artifact, minimumAppBuild, createdAt, source, formatVersion
    }

    init(
        schemaVersion: Int,
        region: String,
        datasetVersion: String,
        osmTimestamp: Date? = nil,
        routingEngine: RoutingEngine,
        artifact: Artifact,
        minimumAppBuild: Int,
        createdAt: Date? = nil,
        source: String? = nil,
        formatVersion: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.region = region
        self.datasetVersion = datasetVersion
        self.osmTimestamp = osmTimestamp
        self.routingEngine = routingEngine
        self.artifact = artifact
        self.minimumAppBuild = minimumAppBuild
        self.createdAt = createdAt
        self.source = source
        self.formatVersion = formatVersion
    }

    func isCompatible(withMobileVersion mobileVersion: String, appBuild: Int) -> Bool {
        schemaVersion == 1
            && region == "luxembourg"
            && routingEngine.valhallaMobileVersion == mobileVersion
            && minimumAppBuild <= appBuild
            && !datasetVersion.isEmpty
            && !artifact.sha256.isEmpty
    }
}

nonisolated struct RoutingDataset: Hashable, Sendable {
    let manifest: RoutingDatasetManifest
    let tileArchiveURL: URL

    var storageRevision: String? = nil
    var version: String { manifest.datasetVersion }
    var revision: String { storageRevision ?? version }
}

nonisolated enum RoutingDataState: Equatable, Sendable {
    case unavailable
    case ready(version: String)
    case checking
    case downloading(progress: Double)
    case installing
    case failed(previousVersionStillAvailable: Bool)
}

nonisolated enum RoutingDatasetError: Error, Equatable {
    case incompatibleManifest
    case invalidVersion
    case archiveMissing
    case archiveSizeMismatch
    case checksumMismatch
    case versionAlreadyInstalled
    case activeDatasetMissing
}

protocol RoutingDatasetValidating: Sendable {
    func validate(_ dataset: RoutingDataset) async throws
}

/// Owns immutable on-device routing graph versions. Downloads are copied into
/// staging, verified and opened before `current.json` changes, so a failed
/// update can never damage the active graph.
actor RoutingDatasetManager {
    static let valhallaMobileVersion = "0.6.3"

    private struct CurrentDataset: Codable {
        let version: String
    }

    private struct FileStamp: Equatable {
        let inode: UInt64
        let size: UInt64
        let modified: Date?
        init(_ url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            modified = attributes[.modificationDate] as? Date
        }
        var revision: String { "\(inode):\(size):\(modified?.timeIntervalSince1970 ?? 0)" }
    }
    private var activeCache: (current: FileStamp, manifest: FileStamp, archive: FileStamp, dataset: RoutingDataset)?
    private let rootURL: URL
    private let versionsURL: URL
    private let stagingURL: URL
    private let currentURL: URL
    private let appBuild: Int
    private let mobileVersion: String

    init(
        rootURL: URL? = nil,
        appBuild: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
        mobileVersion: String = RoutingDatasetManager.valhallaMobileVersion
    ) {
        let defaultRoot = Self.defaultRootURL
        self.rootURL = rootURL ?? defaultRoot
        versionsURL = (rootURL ?? defaultRoot).appendingPathComponent("versions", isDirectory: true)
        stagingURL = (rootURL ?? defaultRoot).appendingPathComponent("staging", isDirectory: true)
        currentURL = (rootURL ?? defaultRoot).appendingPathComponent("current.json")
        self.appBuild = appBuild
        self.mobileVersion = mobileVersion
    }

    nonisolated static var defaultRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Routing", isDirectory: true)
    }

    /// Reads the active manifest with plain file reads, for the synchronous launch check.
    /// Returns `nil` unless `current.json`, the manifest and the tile archive all exist.
    nonisolated static func activeManifest(rootURL: URL? = nil) -> RoutingDatasetManifest? {
        let root = rootURL ?? defaultRootURL
        guard let currentData = try? Data(contentsOf: root.appendingPathComponent("current.json")),
              let current = try? JSONDecoder().decode(CurrentDataset.self, from: currentData) else { return nil }
        let directory = root.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(current.version, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("tiles.tar").path),
              let manifestData = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder.routing.decode(RoutingDatasetManifest.self, from: manifestData)
    }

    func activeDataset() throws -> RoutingDataset? {
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            activeCache = nil; return nil
        }
        let currentStamp = try FileStamp(currentURL)
        if let cached = activeCache, cached.current == currentStamp {
            let directory = versionDirectory(for: cached.dataset.version)
            guard let manifest = try? FileStamp(directory.appendingPathComponent("manifest.json")),
                  let archive = try? FileStamp(cached.dataset.tileArchiveURL) else {
                activeCache = nil; throw RoutingDatasetError.activeDatasetMissing
            }
            if cached.manifest == manifest, cached.archive == archive { return cached.dataset }
        }
        let current = try JSONDecoder().decode(CurrentDataset.self, from: Data(contentsOf: currentURL))
        let manifestURL = versionDirectory(for: current.version).appendingPathComponent("manifest.json")
        let archiveURL = versionDirectory(for: current.version).appendingPathComponent("tiles.tar")
        guard let manifestStamp = try? FileStamp(manifestURL), let archiveStamp = try? FileStamp(archiveURL)
        else { activeCache = nil; throw RoutingDatasetError.activeDatasetMissing }
        let dataset = RoutingDataset(
            manifest: try JSONDecoder.routing.decode(RoutingDatasetManifest.self, from: Data(contentsOf: manifestURL)),
            tileArchiveURL: archiveURL,
            storageRevision: "\(current.version):\(manifestStamp.revision):\(archiveStamp.revision)")
        activeCache = (currentStamp, manifestStamp, archiveStamp, dataset)
        return dataset
    }

    /// Installs an already-downloaded `.tar` archive. The source file is never
    /// mutated, which makes this safe for URLSession's temporary download URLs.
    func install(
        archiveURL: URL,
        manifest: RoutingDatasetManifest,
        validator: any RoutingDatasetValidating
    ) async throws -> RoutingDataset {
        guard manifest.isCompatible(withMobileVersion: mobileVersion, appBuild: appBuild) else {
            throw RoutingDatasetError.incompatibleManifest
        }
        guard isSafeVersion(manifest.datasetVersion) else {
            throw RoutingDatasetError.invalidVersion
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RoutingDatasetError.archiveMissing
        }

        try fileManager.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let destinationDirectory = versionDirectory(for: manifest.datasetVersion)
        guard !fileManager.fileExists(atPath: destinationDirectory.path) else {
            throw RoutingDatasetError.versionAlreadyInstalled
        }

        let incomingDirectory = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: incomingDirectory) }
        try fileManager.createDirectory(at: incomingDirectory, withIntermediateDirectories: false)
        let stagedArchiveURL = incomingDirectory.appendingPathComponent("tiles.tar")
        try fileManager.copyItem(at: archiveURL, to: stagedArchiveURL)

        let attributes = try fileManager.attributesOfItem(atPath: stagedArchiveURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard size == manifest.artifact.sizeBytes else {
            throw RoutingDatasetError.archiveSizeMismatch
        }
        guard try sha256(of: stagedArchiveURL).caseInsensitiveCompare(manifest.artifact.sha256) == .orderedSame else {
            throw RoutingDatasetError.checksumMismatch
        }

        let stagedDataset = RoutingDataset(manifest: manifest, tileArchiveURL: stagedArchiveURL)
        try await validator.validate(stagedDataset)
        try JSONEncoder.routing.encode(manifest).write(
            to: incomingDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        // Both directories live beneath Application Support, so this move is an
        // atomic rename. Existing router instances keep their old immutable
        // archive; nothing they are reading is overwritten.
        try fileManager.moveItem(at: incomingDirectory, to: destinationDirectory)
        try JSONEncoder.routing.encode(CurrentDataset(version: manifest.datasetVersion))
            .write(to: currentURL, options: .atomic)
        return RoutingDataset(manifest: manifest, tileArchiveURL: destinationDirectory.appendingPathComponent("tiles.tar"))
    }

    private func versionDirectory(for version: String) -> URL {
        versionsURL.appendingPathComponent(version, isDirectory: true)
    }

    private func isSafeVersion(_ version: String) -> Bool {
        !version.isEmpty && !version.contains("/") && !version.contains("\\") && !version.contains("..")
    }

    private func sha256(of url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var digest = SHA256()
        while true {
            let chunk = try input.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONEncoder {
    nonisolated static var routing: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var routing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
