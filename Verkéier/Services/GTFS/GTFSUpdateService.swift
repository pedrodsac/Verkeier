import Foundation
import Observation

/// Orchestrates checking for, downloading, validating, and installing GTFS feed
/// updates.
///
/// The actor coordinates a pipeline of injected collaborators — metadata fetch,
/// download, archive extraction, validation, and index building — and persists
/// progress through a `GTFSLocalStore`. It exposes the current
/// `GTFSUpdateStatus` via ``snapshot()`` so the UI can show update state.
actor GTFSUpdateService {
    private let metadataClient: any GTFSMetadataFetching
    private let downloadService: any GTFSDownloading
    private let archiveService: any GTFSArchiveExtracting
    private let validator: GTFSValidator
    private let indexBuilder: GTFSIndexBuilder
    private let store: GTFSLocalStore
    private var currentStatus: GTFSUpdateStatus = .idle
    private var lastFailureMessage: String?

    init(
        metadataClient: any GTFSMetadataFetching = GTFSMetadataClient(),
        downloadService: any GTFSDownloading = GTFSDownloadService(),
        archiveService: any GTFSArchiveExtracting = GTFSArchiveService(),
        validator: GTFSValidator = GTFSValidator(),
        indexBuilder: GTFSIndexBuilder = GTFSIndexBuilder(),
        store: GTFSLocalStore = GTFSLocalStore()
    ) {
        self.metadataClient = metadataClient
        self.downloadService = downloadService
        self.archiveService = archiveService
        self.validator = validator
        self.indexBuilder = indexBuilder
        self.store = store
    }

    func snapshot() async -> GTFSUpdateSnapshot {
        GTFSUpdateSnapshot(
            metadata: try? store.loadMetadata(),
            lastMetadataCheckAt: try? store.loadLastMetadataCheckAt(),
            status: currentStatus,
            lastFailureMessage: lastFailureMessage
        )
    }

    @discardableResult
    func checkForUpdates(now: Date = .now) async -> GTFSUpdateSnapshot {
        currentStatus = .checking
        lastFailureMessage = nil

        do {
            try store.bootstrap()
            let localMetadata = try store.loadMetadata()
            try store.saveLastMetadataCheckAt(now)
            let dataset = try await metadataClient.fetchDataset()
            guard let remote = GTFSResourceSelector.selectLatestGTFSResource(from: dataset) else {
                throw GTFSUpdateError.noGTFSResource
            }

            guard GTFSResourceSelector.shouldDownload(remote: remote, local: localMetadata) else {
                currentStatus = .upToDate
                return await snapshot()
            }

            guard let downloadURL = remote.downloadURL else {
                throw GTFSUpdateError.missingDownloadURL
            }

            let tempRoot = try store.resetTempDirectory()
            defer { store.cleanTempDirectory() }

            let archiveURL = tempRoot.appendingPathComponent("gtfs.zip")
            let extractedURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
            let indexURL = tempRoot.appendingPathComponent("stops-index.json")
            let timetableIndexURL = tempRoot.appendingPathComponent("timetable-index.json")

            try await downloadService.download(from: downloadURL, to: archiveURL)
            try archiveService.unzip(archiveURL, to: extractedURL)
            let feedDirectory = try validator.validatedFeedDirectory(in: extractedURL)
            try indexBuilder.buildStopsIndex(from: feedDirectory, to: indexURL)
            try indexBuilder.buildTimetableIndex(from: feedDirectory, to: timetableIndexURL)

            let metadata = LocalGTFSMetadata(
                resourceId: remote.id,
                title: remote.title ?? "Luxembourg public transport GTFS",
                checksum: remote.checksumValue,
                lastModified: remote.lastModified,
                downloadedAt: now,
                indexedAt: now
            )
            try store.commit(
                feedDirectory: feedDirectory,
                indexURL: indexURL,
                timetableIndexURL: timetableIndexURL,
                metadata: metadata
            )
            currentStatus = .updated

            await MainActor.run {
                NotificationCenter.default.post(name: .gtfsDidUpdate, object: nil)
            }

            return await snapshot()
        } catch {
            currentStatus = .failed
            lastFailureMessage = (error as? LocalizedError)?.errorDescription
                ?? "The GTFS update could not be completed."
            store.cleanTempDirectory()
            return await snapshot()
        }
    }
}

@MainActor
@Observable
final class GTFSUpdateController {
    private let controller: GTFSController
    var snapshot: GTFSUpdateSnapshot = .empty
    var isChecking = false

    init(controller: GTFSController = GTFSController()) {
        self.controller = controller
    }

    func loadSnapshot() {
        Task {
            let savedSnapshot = await controller.updateSnapshot()
            guard !isChecking else { return }
            snapshot = savedSnapshot
        }
    }

    func checkAutomatically() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            snapshot = await controller.checkForUpdates()
            isChecking = false
        }
    }

    func checkManually() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            snapshot = await controller.checkForUpdates()
            isChecking = false
        }
    }
}
