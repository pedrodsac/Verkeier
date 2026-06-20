import CoreLocation
import Foundation

nonisolated struct LocationPoint: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String?
    let latitude: Double
    let longitude: Double

    nonisolated init(
        id: String? = nil,
        name: String? = nil,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id ?? "\(latitude),\(longitude)"
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
