import Foundation

struct RoutePlan: Codable, Hashable, Identifiable, Sendable {
    struct Leg: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let mode: TransportMode
        let routeName: String?
        let origin: LocationPoint
        let destination: LocationPoint
        let departureTime: Date?
        let arrivalTime: Date?
        let distanceMeters: Double?
    }

    let id: String
    let origin: LocationPoint
    let destination: LocationPoint
    let expectedTravelTime: TimeInterval?
    let distanceMeters: Double?
    let legs: [Leg]
    let dataSource: DataSource
}
