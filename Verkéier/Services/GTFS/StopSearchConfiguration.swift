import Foundation

/// Shared timing and bounds for user-initiated GTFS stop searches.
nonisolated enum StopSearchConfiguration {
    /// Wait for a typing pause before starting local and supplemental searches.
    static let debounceInterval: Duration = .milliseconds(500)

    /// Keep result lists small enough for responsive presentation and merging.
    static let resultLimit = 80
}
