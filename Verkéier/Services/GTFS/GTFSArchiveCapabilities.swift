import Foundation

/// A truthful description of the installed schedule feed. Feature code should
/// consult this before presenting data that GTFS does not actually publish.
nonisolated struct GTFSArchiveCapabilities: Sendable, Hashable {
    let supportsScheduledDepartures: Bool
    let supportsScheduledArrivals: Bool
    let supportsTripGeometry: Bool
    let supportsTransfers: Bool
    let supportsBicycleInformation: Bool
    let supportsBlockContinuity: Bool
    let supportsRealtime: Bool
    let supportsFares: Bool
    let supportsStationHierarchy: Bool
    let supportsAccessibilityInformation: Bool

    static let unavailable = GTFSArchiveCapabilities(
        supportsScheduledDepartures: false,
        supportsScheduledArrivals: false,
        supportsTripGeometry: false,
        supportsTransfers: false,
        supportsBicycleInformation: false,
        supportsBlockContinuity: false,
        supportsRealtime: false,
        supportsFares: false,
        supportsStationHierarchy: false,
        supportsAccessibilityInformation: false
    )
}
