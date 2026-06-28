import Foundation

struct RoutePlannerStore {
    private let defaults: UserDefaults

    nonisolated static let shared = RoutePlannerStore(
        defaults: UserDefaults(suiteName: SharedTransitDataStore.appGroupIdentifier) ?? .standard
    )

    private let recentPlacesKey = "RoutePlannerRecentPlaces"
    private let recentStopsKey = "RoutePlannerRecentStops"
    private let commutePresetsKey = "RoutePlannerCommutePresets"

    init(defaults: UserDefaults) {
        self.defaults = defaults
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
