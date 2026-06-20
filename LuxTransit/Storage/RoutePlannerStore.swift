import Foundation

struct RoutePlannerStore {
    private let defaults: UserDefaults

    nonisolated static let shared = RoutePlannerStore(
        defaults: UserDefaults(suiteName: SharedTransitDataStore.appGroupIdentifier) ?? .standard
    )

    private let recentPlacesKey = "RoutePlannerRecentPlaces"
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

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
