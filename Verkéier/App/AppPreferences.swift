import CoreLocation
import Observation
import SwiftUI

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String {
        rawValue
    }

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

    var id: String {
        rawValue
    }

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

    var defaultModePreference: RoutePlannerModePreference {
        didSet { saveString(defaultModePreference.rawValue, forKey: Keys.defaultModePreference) }
    }

    var avoidTightTransfers: Bool {
        didSet { defaults.set(avoidTightTransfers, forKey: Keys.avoidTightTransfers) }
    }

    var preferAccessible: Bool {
        didSet { defaults.set(preferAccessible, forKey: Keys.preferAccessible) }
    }

    /// Plan on static GTFS only: no live departures/delays/cancellations, and a
    /// 15-minute minimum transfer buffer.
    var offlineMode: Bool {
        didSet { defaults.set(offlineMode, forKey: Keys.offlineMode) }
    }

    var showBikeShareStations: Bool {
        didSet { defaults.set(showBikeShareStations, forKey: Keys.showBikeShareStations) }
    }

    var showBusStops: Bool {
        didSet { defaults.set(showBusStops, forKey: Keys.showBusStops) }
    }

    var showTramStops: Bool {
        didSet { defaults.set(showTramStops, forKey: Keys.showTramStops) }
    }

    var showTrainStations: Bool {
        didSet { defaults.set(showTrainStations, forKey: Keys.showTrainStations) }
    }

    var defaultReminderLeadTimeMinutes: Int {
        didSet { defaults.set(defaultReminderLeadTimeMinutes, forKey: Keys.defaultReminderLeadTime) }
    }

    static let reminderLeadTimeOptions = [5, 10, 15, 20]

    init(defaults: UserDefaults = SharedTransitDataStore.userDefaults) {
        self.defaults = defaults
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        distanceUnit = DistanceUnitPreference(rawValue: defaults.string(forKey: Keys.distanceUnit) ?? "") ?? .metric
        defaultModePreference = RoutePlannerModePreference(rawValue: defaults
            .string(forKey: Keys.defaultModePreference) ?? "") ?? .any
        avoidTightTransfers = defaults.bool(forKey: Keys.avoidTightTransfers)
        preferAccessible = defaults.bool(forKey: Keys.preferAccessible)
        offlineMode = defaults.bool(forKey: Keys.offlineMode)
        showBikeShareStations = Self.savedBool(
            forKey: Keys.showBikeShareStations,
            defaults: defaults
        )
        showBusStops = Self.savedBool(forKey: Keys.showBusStops, defaults: defaults)
        showTramStops = Self.savedBool(forKey: Keys.showTramStops, defaults: defaults)
        showTrainStations = Self.savedBool(forKey: Keys.showTrainStations, defaults: defaults)
        let saved = defaults.integer(forKey: Keys.defaultReminderLeadTime)
        defaultReminderLeadTimeMinutes = saved > 0 ? saved : 5
    }

    var defaultRouteFilters: RoutePlannerFilters {
        RoutePlannerFilters(
            modePreference: defaultModePreference,
            avoidTightTransfers: avoidTightTransfers,
            preferAccessible: preferAccessible
        )
    }

    func formattedDistance(_ meters: CLLocationDistance) -> String {
        switch distanceUnit {
        case .metric:
            if meters < 1000 { return "\(Int(meters.rounded())) m" }
            return String(format: "%.1f km", meters / 1000)
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

    private static func savedBool(forKey key: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    private enum Keys {
        static let appearance = "AppPreferences.appearance"
        static let distanceUnit = "AppPreferences.distanceUnit"
        static let defaultModePreference = "AppPreferences.defaultModePreference"
        static let avoidTightTransfers = "AppPreferences.avoidTightTransfers"
        static let preferAccessible = "AppPreferences.preferAccessible"
        static let offlineMode = "AppPreferences.offlineMode"
        static let showBikeShareStations = "AppPreferences.showBikeShareStations"
        static let showBusStops = "AppPreferences.showBusStops"
        static let showTramStops = "AppPreferences.showTramStops"
        static let showTrainStations = "AppPreferences.showTrainStations"
        static let defaultReminderLeadTime = "AppPreferences.defaultReminderLeadTime"
    }
}
