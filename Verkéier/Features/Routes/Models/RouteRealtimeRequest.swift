import Foundation

nonisolated struct RouteRealtimeRequest: Hashable, Sendable {
    let optionID: String
    let generation: Int
    let origin: LocationPoint
    let destination: LocationPoint
}
