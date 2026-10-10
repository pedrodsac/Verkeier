import Foundation

/// A linked run keeps its stop sequences and live reports separate from the
/// incoming run, even when both runs visit the same stop.
nonisolated struct TripDetailContinuation: Hashable, Sendable {
    let selection: TripDetailSelection
    let snapshot: TripDetailSnapshot
}
