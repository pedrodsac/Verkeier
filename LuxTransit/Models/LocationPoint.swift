import CoreLocation
import Foundation

/// A named geographic coordinate.
///
/// A lightweight, `Codable` and `Sendable` alternative to
/// `CLLocationCoordinate2D` used throughout the domain models. Convert to a
/// MapKit coordinate with ``coordinate``.
nonisolated struct LocationPoint: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier; defaults to `"latitude,longitude"` when not supplied.
    let id: String
    /// Optional place name.
    let name: String?
    let latitude: Double
    let longitude: Double

    /// Creates a location point.
    ///
    /// - Parameter id: Explicit identifier; when `nil`, a `"lat,lon"` string is
    ///   synthesized from the coordinates.
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

    /// The point as a MapKit / CoreLocation coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
