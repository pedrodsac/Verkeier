import Foundation

/// A stop the rider has saved for quick access.
///
/// The value type mirrored to SwiftData persistence (`PersistedFavouriteStop`)
/// and shared with the widget and App Intents targets. It denormalizes the
/// stop's name and location so favourites render without a GTFS lookup.
struct FavouriteStop: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier; defaults to ``stopId`` when not supplied.
    let id: String
    /// Identifier of the underlying ``Stop``.
    let stopId: String
    /// Stop name captured at save time.
    let name: String
    /// Optional locality captured at save time.
    let locality: String?
    /// Stop location captured at save time.
    let location: LocationPoint
    /// When the favourite was created, used for ordering.
    let createdAt: Date

    /// Creates a favourite.
    ///
    /// - Parameter id: Explicit identifier; when `nil`, ``stopId`` is used.
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
