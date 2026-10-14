import Foundation

/// Identifies everything that can change a stored walking result. It is built
/// from the manifest, not from file stamps, so it survives backup restores.
///
/// Bump `algorithmRevision` whenever a result-affecting walking change lands:
/// `ShortWalkingRouteSearch` thresholds, `WalkingPathRequest`/`WalkingPathResponse`,
/// `ValhallaWalkingRouter.decodePolyline6`, `LocalFirstWalkingRouter.uncachedRoute`,
/// the calibration, or the valhalla-mobile / openapi-models package pins.
nonisolated struct TransferWalkGraphIdentity: Hashable, Sendable {
    static let algorithmRevision = 1

    let value: String

    init(manifest: RoutingDatasetManifest, runtimeMobileVersion: String = RoutingDatasetManager.valhallaMobileVersion) {
        value = [
            "alg=\(Self.algorithmRevision)",
            "dataset=\(manifest.datasetVersion)",
            "sha256=\(manifest.artifact.sha256.lowercased())",
            "core=\(manifest.routingEngine.valhallaCoreCommit)",
            "mobile=\(manifest.routingEngine.valhallaMobileVersion)/\(runtimeMobileVersion)",
            "pafendall=\(PafendallFunicularConnection.revision)",
            "calibration=\(WalkingDurationCalibration.multiplier.bitPattern)"
        ].joined(separator: ";")
    }
}

nonisolated extension RoutingDataset {
    var transferWalkIdentity: TransferWalkGraphIdentity { .init(manifest: manifest) }
}

nonisolated extension RoutingDatasetManifest {
    var transferWalkIdentity: TransferWalkGraphIdentity { .init(manifest: self) }
}
