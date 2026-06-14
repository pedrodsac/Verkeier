import Foundation
import Observation

actor GTFSUpdateService {
    private let metadataClient: any GTFSMetadataFetching
    private let downloadService: any GTFSDownloading
    private let archiveService: any GTFSArchiveExtracting
    private let validator: GTFSValidator
    private let indexBuilder: GTFSIndexBuilder
    private let store: GTFSLocalStore
    private let calendar: Calendar
    private var currentStatus: GTFSUpdateStatus = .idle

    init(
        metadataClient: any GTFSMetadataFetching = GTFSMetadataClient(),
        downloadService: any GTFSDownloading = GTFSDownloadService(),
        archiveService: any GTFSArchiveExtracting = GTFSArchiveService(),
        validator: GTFSValidator = GTFSValidator(),
        indexBuilder: GTFSIndexBuilder = GTFSIndexBuilder(),
        store: GTFSLocalStore = GTFSLocalStore(),
        calendar: Calendar = .current
    ) {
        self.metadataClient = metadataClient
        self.downloadService = downloadService
        self.archiveService = archiveService
        self.validator = validator
        self.indexBuilder = indexBuilder
        self.store = store
        self.calendar = calendar
    }

    func snapshot() async -> GTFSUpdateSnapshot {
        GTFSUpdateSnapshot(
            metadata: try? store.loadMetadata(),
            lastMetadataCheckAt: try? store.loadLastMetadataCheckAt(),
            status: currentStatus
        )
    }

    @discardableResult
    func checkForUpdates(force: Bool = false, now: Date = .now) async -> GTFSUpdateSnapshot {
        currentStatus = .checking

        do {
            try store.bootstrap()
            let localMetadata = try store.loadMetadata()
            if !force,
               store.hasCurrentFeed(),
               let lastCheck = try store.loadLastMetadataCheckAt(),
               calendar.isDate(lastCheck, inSameDayAs: now) {
                currentStatus = .upToDate
                return await snapshot()
            }

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

            try await downloadService.download(from: downloadURL, to: archiveURL)
            try archiveService.unzip(archiveURL, to: extractedURL)
            let feedDirectory = try validator.validatedFeedDirectory(in: extractedURL)
            try indexBuilder.buildStopsIndex(from: feedDirectory, to: indexURL)

            let metadata = LocalGTFSMetadata(
                resourceId: remote.id,
                title: remote.title ?? "Luxembourg public transport GTFS",
                checksum: remote.checksumValue,
                lastModified: remote.lastModified,
                downloadedAt: now,
                indexedAt: now
            )
            try store.commit(feedDirectory: feedDirectory, indexURL: indexURL, metadata: metadata)
            currentStatus = .updated

            await MainActor.run {
                NotificationCenter.default.post(name: .gtfsDidUpdate, object: nil)
            }

            return await snapshot()
        } catch {
            currentStatus = .failed
            store.cleanTempDirectory()
            return await snapshot()
        }
    }
}

@MainActor
@Observable
final class GTFSUpdateController {
    private let service: GTFSUpdateService
    var snapshot: GTFSUpdateSnapshot = .empty
    var isChecking = false

    init(service: GTFSUpdateService = GTFSUpdateService()) {
        self.service = service
    }

    func loadSnapshot() {
        Task {
            snapshot = await service.snapshot()
        }
    }

    func checkAutomatically() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            snapshot = await service.checkForUpdates(force: false)
            isChecking = false
        }
    }

    func checkManually() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            snapshot = await service.checkForUpdates(force: true)
            isChecking = false
        }
    }
}
