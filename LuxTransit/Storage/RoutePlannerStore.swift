import Foundation

struct RoutePlannerStore {
    private let defaults: UserDefaults

    nonisolated static let shared = RoutePlannerStore(
        defaults: UserDefaults(suiteName: SharedTransitDataStore.appGroupIdentifier) ?? .standard
    )

    private let recentPlacesKey = "RoutePlannerRecentPlaces"
    private let recentStopsKey = "RoutePlannerRecentStops"
    private let recentTripsKey = "RoutePlannerRecentTrips"
    private let commutePresetsKey = "RoutePlannerCommutePresets"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Removes all planner data (recent places/stops/trips and commute presets).
    func clearAll() {
        for item in [recentPlacesKey, recentStopsKey, recentTripsKey, commutePresetsKey] {
            defaults.removeObject(forKey: item)
        }
    }

    func recentPlaces() -> [RoutePlace] {
        load([RoutePlace].self, forKey: recentPlacesKey) ?? []
    }

    func saveRecentPlaces(_ places: [RoutePlace]) {
        save(places, forKey: recentPlacesKey)
    }

    func commutePresets() -> [RouteCommutePreset] {
        load([RouteCommutePreset].self, forKey: commutePresetsKey) ?? []
    }

    func saveCommutePresets(_ presets: [RouteCommutePreset]) {
        save(presets, forKey: commutePresetsKey)
    }

    func recordRecentPlace(_ place: RoutePlace, limit: Int = 8) -> [RoutePlace] {
        guard place.source != .currentLocation else {
            return recentPlaces()
        }

        var updated = recentPlaces().filter { $0.id != place.id }
        updated.insert(place, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        saveRecentPlaces(updated)
        return updated
    }

    /// The most recently planned origin→destination pairs, newest first.
    func recentTrips() -> [RouteCommutePreset] {
        load([RouteCommutePreset].self, forKey: recentTripsKey) ?? []
    }

    /// Records a planned trip, de-duplicating by origin+destination and capping
    /// the list. Returns the updated list. Skips current-location-only origins so
    /// re-use stays meaningful.
    func recordRecentTrip(origin: RoutePlace?, destination: RoutePlace, limit: Int = 10) -> [RouteCommutePreset] {
        let title = origin.map { "\($0.title) → \(destination.title)" } ?? destination.title
        let trip = RouteCommutePreset(title: title, origin: origin, destination: destination)
        var updated = recentTrips().filter {
            !($0.origin == trip.origin && $0.destination == trip.destination)
        }
        updated.insert(trip, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        save(updated, forKey: recentTripsKey)
        return updated
    }

    func recentStops() -> [Stop] {
        load([Stop].self, forKey: recentStopsKey) ?? []
    }

    func saveRecentStops(_ stops: [Stop]) {
        save(stops, forKey: recentStopsKey)
    }

    func recordRecentStop(_ stop: Stop, limit: Int = 8) -> [Stop] {
        guard stop.dataSource != .mock else {
            return recentStops()
        }

        var updated = recentStops().filter { $0.id != stop.id }
        updated.insert(stop, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        saveRecentStops(updated)
        return updated
    }

    private func save(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
