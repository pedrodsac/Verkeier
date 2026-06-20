import Foundation

nonisolated enum RouteLoadingPhase: String, Hashable, Sendable {
    case idle
    case waitingForLocation
    case calculating

    var isCalculating: Bool {
        self == .calculating
    }

    var isWaitingForLocation: Bool {
        self == .waitingForLocation
    }
}
