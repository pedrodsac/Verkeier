import Foundation

/// Everything the decision depends on, read from small files only.
nonisolated struct RoutingOptimisationInputs: Equatable, Sendable {
    var mode: TransferWalkMode
    /// Identity of the active walking graph.
    var activeGraph: String?
    /// Identity of a bundled graph that differs from the active one and is about to be installed.
    var pendingBundledGraph: String?
    /// Identity of the installed, unexpired timetable.
    var timetable: String?
    var header: TransferWalkTable.Header?
    /// The ledger has recorded too many unfinished attempts for this target.
    var blockedByLedger: Bool
}

nonisolated enum RoutingOptimisationDecision {
    /// The graph the stored walks must match once launch preparation finishes.
    static func expectedGraph(_ inputs: RoutingOptimisationInputs) -> String? {
        inputs.pendingBundledGraph ?? inputs.activeGraph
    }

    static func requirement(_ inputs: RoutingOptimisationInputs) -> RoutingOptimisationRequirement {
        guard inputs.mode != .off, let graph = expectedGraph(inputs) else { return .notNeeded }
        let raw: RoutingOptimisationRequirement
        if let timetable = inputs.timetable {
            if inputs.header?.graphIdentity != graph { raw = .needsFull }
            else if inputs.header?.timetableIdentity != timetable { raw = .needsIncremental }
            else { raw = .notNeeded }
        } else {
            // Nothing to wait for if walks for this graph already exist; the next
            // launch with a timetable will extend them.
            raw = inputs.header?.graphIdentity == graph ? .notNeeded : .waitingForTimetable
        }
        return raw.needsWork && inputs.blockedByLedger ? .notNeeded : raw
    }
}

nonisolated struct RoutingOptimisationEnvironment: Sendable {
    var mode: TransferWalkMode
    var routingRootURL: URL
    var gtfsDirectoryURL: URL
    var bundledManifestURL: URL?
    var store: TransferWalkStore
    var ledger: RoutingOptimisationAttemptLedger
    /// Compatibility inputs for the bundled manifest.
    var appBuild: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0

    static func production(store: TransferWalkStore, mode: TransferWalkMode = TransferWalkSettings.mode) -> Self {
        Self(mode: mode, routingRootURL: RoutingDatasetManager.defaultRootURL,
             gtfsDirectoryURL: MobiliteitGTFSService.defaultDirectoryURL,
             bundledManifestURL: Bundle.main.url(forResource: "luxembourg-walking-manifest", withExtension: "json"),
             store: store, ledger: RoutingOptimisationAttemptLedger())
    }
}

/// Synchronous launch-time evaluation. It reads a handful of small files and never
/// opens SQLite, hashes the table, or waits for the walking graph installation.
nonisolated enum RoutingOptimisationLaunchCheck {
    static func bundledManifest(in environment: RoutingOptimisationEnvironment) -> RoutingDatasetManifest? {
        guard let url = environment.bundledManifestURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.routing.decode(RoutingDatasetManifest.self, from: data)
    }

    static func inputs(in environment: RoutingOptimisationEnvironment) -> RoutingOptimisationInputs {
        let active = RoutingDatasetManager.activeManifest(rootURL: environment.routingRootURL)
        var pending: String?
        if let bundled = bundledManifest(in: environment), bundled.datasetVersion != active?.datasetVersion,
           environment.ledger.failedBundledInstall != bundledInstallIdentity(bundled) {
            pending = bundled.transferWalkIdentity.value
        }
        let timetable = MobiliteitGTFSService.installedTimetableIdentity(directory: environment.gtfsDirectoryURL)
        var inputs = RoutingOptimisationInputs(
            mode: environment.mode, activeGraph: active?.transferWalkIdentity.value,
            pendingBundledGraph: pending, timetable: timetable,
            header: environment.store.header(), blockedByLedger: false)
        if let graph = RoutingOptimisationDecision.expectedGraph(inputs), let timetable {
            inputs.blockedByLedger = environment.ledger.isBlocked(target: target(graph: graph, timetable: timetable))
        }
        return inputs
    }

    static func requirement(in environment: RoutingOptimisationEnvironment) -> RoutingOptimisationRequirement {
        RoutingOptimisationDecision.requirement(inputs(in: environment))
    }

    static func target(graph: String, timetable: String) -> String { "\(graph)|\(timetable)" }

    static func bundledInstallIdentity(_ manifest: RoutingDatasetManifest) -> String {
        "\(manifest.datasetVersion)|\(manifest.artifact.sha256.lowercased())"
    }
}
