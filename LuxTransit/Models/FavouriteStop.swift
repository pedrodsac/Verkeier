import Foundation

struct FavouriteStop: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let stopId: String
    let name: String
    let locality: String?
    let location: LocationPoint
    let createdAt: Date

    init(
        id: String? = nil,
        stopId: String,
        name: String,
        locality: String? = nil,
        location: LocationPoint,
        createdAt: Date = .now
    ) {
        self.id = id ?? stopId
        self.stopId = stopId
        self.name = name
        self.locality = locality
        self.location = location
        self.createdAt = createdAt
    }
}
