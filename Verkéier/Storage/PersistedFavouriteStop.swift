import Foundation
import SwiftData

@Model
final class PersistedFavouriteStop {
    @Attribute(.unique) var stopId: String
    var name: String
    var locality: String?
    var latitude: Double
    var longitude: Double
    var modesRawValue: String
    var platformIdsRawValue: String?
    var createdAt: Date
    /// Optional rider-set grouping label, e.g. "Home", "Work". `nil` = unlabelled.
    var label: String?

    init(stop: Stop, createdAt: Date = .now) {
        stopId = stop.id
        name = stop.name
        locality = stop.locality
        latitude = stop.location.latitude
        longitude = stop.location.longitude
        modesRawValue = stop.modes.map(\.rawValue).joined(separator: ",")
        platformIdsRawValue = stop.platformIds.joined(separator: ",")
        self.createdAt = createdAt
    }

    var stop: Stop {
        Stop(
            id: stopId,
            name: name,
            locality: locality,
            location: LocationPoint(id: stopId, name: name, latitude: latitude, longitude: longitude),
            modes: modesRawValue
                .split(separator: ",")
                .compactMap { TransportMode(rawValue: String($0)) },
            dataSource: .local,
            platformIds: platformIds
        )
    }

    private var platformIds: [String] {
        guard let platformIdsRawValue else { return [stopId] }
        let ids = platformIdsRawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ids.isEmpty ? [stopId] : ids
    }
}
