import CoreLocation
import Observation
import SwiftUI

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum DistanceUnitPreference: String, Codable, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: "Metric (km)"
        case .imperial: "Imperial (mi)"
        }
    }
}

@Observable
final class AppPreferences {
    nonisolated static let shared = AppPreferences()

    private let defaults: UserDefaults

    var appearance: AppearancePreference {
        didSet { saveString(appearance.rawValue, forKey: Keys.appearance) }
    }
    var distanceUnit: DistanceUnitPreference {
        didSet { saveString(distanceUnit.rawValue, forKey: Keys.distanceUnit) }
    }
    var defaultRouteSort: RoutePlannerSortOption {
        didSet { saveString(defaultRouteSort.rawValue, forKey: Keys.defaultRouteSort) }
    }
    var defaultModePreference: RoutePlannerModePreference {
        didSet { saveString(defaultModePreference.rawValue, forKey: Keys.defaultModePreference) }
    }
    var avoidTightTransfers: Bool {
        didSet { defaults.set(avoidTightTransfers, forKey: Keys.avoidTightTransfers) }
    }
    var preferAccessible: Bool {
        didSet { defaults.set(preferAccessible, forKey: Keys.preferAccessible) }
    }
    var defaultReminderLeadTimeMinutes: Int {
        didSet { defaults.set(defaultReminderLeadTimeMinutes, forKey: Keys.defaultReminderLeadTime) }
    }

    static let reminderLeadTimeOptions = [5, 10, 15, 20]

    init(defaults: UserDefaults = SharedTransitDataStore.userDefaults) {
        self.defaults = defaults
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        distanceUnit = DistanceUnitPreference(rawValue: defaults.string(forKey: Keys.distanceUnit) ?? "") ?? .metric
        defaultRouteSort = RoutePlannerSortOption(rawValue: defaults.string(forKey: Keys.defaultRouteSort) ?? "") ?? .fastest
        defaultModePreference = RoutePlannerModePreference(rawValue: defaults.string(forKey: Keys.defaultModePreference) ?? "") ?? .any
        avoidTightTransfers = defaults.bool(forKey: Keys.avoidTightTransfers)
        preferAccessible = defaults.bool(forKey: Keys.preferAccessible)
        let saved = defaults.integer(forKey: Keys.defaultReminderLeadTime)
        defaultReminderLeadTimeMinutes = saved > 0 ? saved : 5
    }

    var defaultRouteFilters: RoutePlannerFilters {
        RoutePlannerFilters(
            sort: defaultRouteSort,
            modePreference: defaultModePreference,
            avoidTightTransfers: avoidTightTransfers,
            preferAccessible: preferAccessible
        )
    }

    func formattedDistance(_ meters: CLLocationDistance) -> String {
        switch distanceUnit {
        case .metric:
            if meters < 1_000 { return "\(Int(meters.rounded())) m" }
            return String(format: "%.1f km", meters / 1_000)
        case .imperial:
            let feet = meters * 3.28084
            if feet < 528 { return "\(Int(feet.rounded())) ft" }
            return String(format: "%.1f mi", meters / 1609.344)
        }
    }

    func formattedWalkingMinutes(for meters: CLLocationDistance) -> String {
        let minutes = max(1, Int((meters / 1.33 / 60).rounded()))
        return "\(minutes) min"
    }

    private func saveString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let appearance = "AppPreferences.appearance"
        static let distanceUnit = "AppPreferences.distanceUnit"
        static let defaultRouteSort = "AppPreferences.defaultRouteSort"
        static let defaultModePreference = "AppPreferences.defaultModePreference"
        static let avoidTightTransfers = "AppPreferences.avoidTightTransfers"
        static let preferAccessible = "AppPreferences.preferAccessible"
        static let defaultReminderLeadTime = "AppPreferences.defaultReminderLeadTime"
    }
}
