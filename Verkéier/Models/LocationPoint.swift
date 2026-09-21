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
    /// Exact GTFS stop identifier when this point represents a transit stop.
    /// Free-form addresses and device locations leave this `nil`.
    let transitStopID: String?

    /// Creates a location point.
    ///
    /// - Parameter id: Explicit identifier; when `nil`, a `"lat,lon"` string is
    ///   synthesized from the coordinates.
    nonisolated init(
        id: String? = nil,
        name: String? = nil,
        latitude: Double,
        longitude: Double,
        transitStopID: String? = nil
    ) {
        self.id = id ?? "\(latitude),\(longitude)"
        self.name = name?.stationDisplayName
        self.latitude = latitude
        self.longitude = longitude
        self.transitStopID = transitStopID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case transitStopID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)?.stationDisplayName
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        transitStopID = try container.decodeIfPresent(String.self, forKey: .transitStopID)
    }

    /// The point as a MapKit / CoreLocation coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
