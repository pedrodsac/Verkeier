import Foundation

/// Opens a staged graph with the runtime engine before it becomes active.
nonisolated struct ValhallaRoutingDatasetValidator: RoutingDatasetValidating {
    func validate(_ dataset: RoutingDataset) async throws {
        let router = try ValhallaWalkingRouter(
            tileArchiveURL: dataset.tileArchiveURL,
            datasetVersion: "validation-\(UUID().uuidString)"
        )
        let origin = LocationPoint(latitude: 49.6116, longitude: 6.1319)
        let destination = LocationPoint(latitude: 49.6120, longitude: 6.1325)
        let estimates = try await router.estimates(
            from: origin,
            to: [WalkingDestination(id: "smoke", location: destination)]
        )
        guard estimates.count == 1, estimates[0].distanceMeters > 0 else {
            throw WalkingRoutingError.invalidResponse
        }
        let route = try await router.route(from: origin, to: destination)
        guard route.coordinates.count >= 2, route.distanceMeters > 0 else {
            throw WalkingRoutingError.invalidResponse
        }
    }
}

/// Installs the immutable Valhalla graph shipped with the app on first launch.
/// The archive remains in the read-only app bundle; the installed copy lets
/// Valhalla memory-map it from Application Support at runtime.
actor BundledRoutingDatasetInstaller {
    private let manifestURL: URL?
    private let archiveURL: URL?
    private let datasetManager: RoutingDatasetManager
    private let validator: any RoutingDatasetValidating

    init(
        manifestURL: URL?,
        archiveURL: URL?,
        datasetManager: RoutingDatasetManager,
        validator: any RoutingDatasetValidating = ValhallaRoutingDatasetValidator()
    ) {
        self.manifestURL = manifestURL
        self.archiveURL = archiveURL
        self.datasetManager = datasetManager
        self.validator = validator
    }

    init(
        bundle: Bundle = .main,
        datasetManager: RoutingDatasetManager,
        validator: any RoutingDatasetValidating = ValhallaRoutingDatasetValidator()
    ) {
        manifestURL = bundle.url(forResource: "luxembourg-walking-manifest", withExtension: "json")
        archiveURL = bundle.url(forResource: "luxembourg-walking-tiles", withExtension: "tar")
        self.datasetManager = datasetManager
        self.validator = validator
    }

    /// Returns the already active version when no bundled graph is present.
    /// This keeps development builds usable before the release resource has
    /// been generated, while production builds install the graph exactly once.
    func installIfNeeded() async -> RoutingDataState {
        let existing = try? await datasetManager.activeDataset()
        guard let manifestURL, let archiveURL else {
            return existing.map { .ready(version: $0.version) } ?? .unavailable
        }

        do {
            let manifest = try JSONDecoder.routing.decode(
                RoutingDatasetManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            guard existing?.version != manifest.datasetVersion else {
                return .ready(version: manifest.datasetVersion)
            }
            let installed = try await datasetManager.install(
                archiveURL: archiveURL,
                manifest: manifest,
                validator: validator
            )
            return .ready(version: installed.version)
        } catch {
            return .failed(previousVersionStillAvailable: existing != nil)
        }
    }
}
