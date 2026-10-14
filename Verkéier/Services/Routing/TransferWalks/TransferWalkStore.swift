import Foundation

/// File identity used to discard only the exact file that failed validation.
nonisolated struct TransferWalkFileStamp: Equatable, Sendable {
    let inode: UInt64
    let size: UInt64
}

nonisolated enum TransferWalkLoadResult: Sendable {
    case missing
    case table(TransferWalkTable)
    /// The file exists but failed validation; it can be discarded.
    case invalid(TransferWalkFileStamp)
    /// The file could not be read (for example before first unlock); never discard.
    case unreadable
}

/// Owns the single transfer walk file under Application Support.
nonisolated struct TransferWalkStore: Sendable {
    static let fileName = "transfer-walks.bin"

    let directoryURL: URL

    var fileURL: URL { directoryURL.appendingPathComponent(Self.fileName) }

    init(directoryURL: URL) { self.directoryURL = directoryURL }

    static func makeDefault() -> TransferWalkStore {
        if let override = TransferWalkSettings.storeDirectoryOverride {
            return TransferWalkStore(directoryURL: override)
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TransferWalkStore(
            directoryURL: root.appendingPathComponent("Routing", isDirectory: true)
                .appendingPathComponent("transfer-walks", isDirectory: true)
        )
    }

    /// Cheap check used at launch: the first few kilobytes, no hashing.
    func header() -> TransferWalkTable.Header? { TransferWalkTable.readHeader(at: fileURL) }

    func load() -> TransferWalkLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL, options: .alwaysMapped) else { return .unreadable }
        do { return .table(try TransferWalkTable(data: data)) } catch is TransferWalkTableError {
            return stamp().map { .invalid($0) } ?? .unreadable
        } catch { return .unreadable }
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes the file only if it is still the one that failed validation, so
    /// a freshly written valid table is never deleted by a stale decision.
    func discard(ifStillMatching stamp: TransferWalkFileStamp) {
        guard self.stamp() == stamp else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func stamp() -> TransferWalkFileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { return nil }
        return TransferWalkFileStamp(
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
