import Foundation

nonisolated struct RouteRealtimeRequest: Hashable, Sendable {
    let generation: Int
    let origin: LocationPoint
    let destination: LocationPoint
}
