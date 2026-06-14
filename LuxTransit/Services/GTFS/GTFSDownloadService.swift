import Foundation

nonisolated protocol GTFSDownloading: Sendable {
    func download(from url: URL, to destination: URL) async throws
}

nonisolated struct GTFSDownloadService: GTFSDownloading {
    private let session: URLSession

    init(session: URLSession = .gtfsUpdateSession) {
        self.session = session
    }

    func download(from url: URL, to destination: URL) async throws {
        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GTFSUpdateError.downloadFailed
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }
}
