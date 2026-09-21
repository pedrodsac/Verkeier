import Foundation

/// Opens a staged graph with the same local Valhalla code used at runtime and
/// proves both supported query shapes work before activation.
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

/// Foreground-triggered update checker. It deliberately keeps an existing
/// graph in service throughout transfer and validation.
actor RoutingDatasetUpdateService {
    private let manifestURL: URL?
    private let datasetManager: RoutingDatasetManager
    private let validator: any RoutingDatasetValidating
    private let session: URLSession
    private let defaults: UserDefaults
    private let lastCheckKey = "routingDatasetLastManifestCheck"

    init(
        manifestURL: URL?,
        datasetManager: RoutingDatasetManager,
        validator: any RoutingDatasetValidating = ValhallaRoutingDatasetValidator(),
        defaults: UserDefaults = .standard
    ) {
        self.manifestURL = manifestURL
        self.datasetManager = datasetManager
        self.validator = validator
        self.defaults = defaults
        let configuration = URLSessionConfiguration.background(withIdentifier: "dev.pedrocordeiro.verkeier.routing-data")
        configuration.isDiscretionary = true
        session = URLSession(configuration: configuration)
    }

    func checkForUpdateIfDue(force: Bool = false) async -> RoutingDataState {
        let existing = try? await datasetManager.activeDataset()
        guard let manifestURL else {
            let state: RoutingDataState = existing.map { .ready(version: $0.version) } ?? .unavailable
            debugLog("Routing dataset status: \(description(of: state)); no manifest URL is configured.")
            return state
        }
        let lastCheck = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard force || Date.now.timeIntervalSince(lastCheck) >= 24 * 60 * 60 else {
            let state: RoutingDataState = existing.map { .ready(version: $0.version) } ?? .unavailable
            debugLog("Routing dataset status: \(description(of: state)); update check is not due yet.")
            return state
        }
        defaults.set(Date.now, forKey: lastCheckKey)
        debugLog("Routing dataset update: checking \(manifestURL.absoluteString); active dataset: \(existing?.version ?? "none").")

        do {
            let (manifestData, _) = try await session.data(from: manifestURL)
            let manifest = try JSONDecoder.routing.decode(RoutingDatasetManifest.self, from: manifestData)
            if existing?.version == manifest.datasetVersion {
                let state = RoutingDataState.ready(version: manifest.datasetVersion)
                debugLog("Routing dataset status: \(description(of: state)); already current.")
                return state
            }
            debugLog("Routing dataset update: downloading version \(manifest.datasetVersion).")
            let (archiveURL, _) = try await session.download(from: manifest.artifact.url)
            debugLog("Routing dataset update: validating and installing version \(manifest.datasetVersion).")
            _ = try await datasetManager.install(
                archiveURL: archiveURL,
                manifest: manifest,
                validator: validator
            )
            let state = RoutingDataState.ready(version: manifest.datasetVersion)
            debugLog("Routing dataset status: \(description(of: state)).")
            return state
        } catch {
            let state = RoutingDataState.failed(previousVersionStillAvailable: existing != nil)
            debugLog("Routing dataset status: \(description(of: state)); error: \(error).")
            return state
        }
    }

    private func description(of state: RoutingDataState) -> String {
        switch state {
        case .unavailable: "unavailable"
        case let .ready(version): "ready (version \(version))"
        case .checking: "checking"
        case let .downloading(progress): "downloading (\(Int(progress * 100))%)"
        case .installing: "installing"
        case let .failed(previousVersionStillAvailable):
            "failed (previous dataset available: \(previousVersionStillAvailable))"
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Routing] \(message())")
        #endif
    }
}
