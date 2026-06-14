import Foundation

struct Stop: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let locality: String?
    let location: LocationPoint
    let modes: [TransportMode]
    let dataSource: DataSource

    init(
        id: String,
        name: String,
        locality: String? = nil,
        location: LocationPoint,
        modes: [TransportMode] = [],
        dataSource: DataSource
    ) {
        self.id = id
        self.name = name
        self.locality = locality
        self.location = location
        self.modes = modes
        self.dataSource = dataSource
    }
}
