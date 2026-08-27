import Foundation
import Testing
@testable import Verkeier

struct AppPreferencesTests {
    @Test func mapPinPreferencesDefaultToVisible() {
        let defaults = UserDefaults(suiteName: "AppPreferencesTests-defaults-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)

        #expect(preferences.showBikeShareStations)
        #expect(preferences.showBusStops)
        #expect(preferences.showTramStops)
        #expect(preferences.showTrainStations)
    }

    @Test func mapPinPreferencesPersist() {
        let defaults = UserDefaults(suiteName: "AppPreferencesTests-persistence-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)

        preferences.showBikeShareStations = false
        preferences.showBusStops = false
        preferences.showTramStops = false
        preferences.showTrainStations = false

        let restored = AppPreferences(defaults: defaults)

        #expect(!restored.showBikeShareStations)
        #expect(!restored.showBusStops)
        #expect(!restored.showTramStops)
        #expect(!restored.showTrainStations)
    }
}
