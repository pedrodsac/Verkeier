import Foundation

/// The transient state of an in-progress route calculation, used to drive
/// progress and placeholder UI.
nonisolated enum RouteLoadingPhase: String, Hashable, Sendable {
    /// No calculation running.
    case idle
    /// Blocked waiting for a device location fix before planning.
    case waitingForLocation
    /// Actively computing routes.
    case calculating

    /// Convenience flag for ``calculating``.
    var isCalculating: Bool {
        self == .calculating
    }

    /// Convenience flag for ``waitingForLocation``.
    var isWaitingForLocation: Bool {
        self == .waitingForLocation
    }
}
