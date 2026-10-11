import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

struct RouteTransportFiltersTests {
    @Test func selectedModesRestrictTransitRouting() {
        let preferences = RoutePlannerFilters(includedModes: [.bus, .funicular]).packagePreferences
        #expect(preferences.allowedModes.contains(routeType: 3))
        #expect(preferences.allowedModes.contains(routeType: 700))
        #expect(preferences.allowedModes.contains(routeType: 7))
        #expect(!preferences.allowedModes.contains(routeType: 0))
        #expect(!preferences.allowedModes.contains(routeType: 2))
        #expect(preferences.preferredMode == nil)
    }

    @Test func walkingAndBikeOnlyExcludeAllTransit() {
        #expect(RoutePlannerFilters(includedModes: [.bicycle]).packagePreferences.allowedModes.rawValue == 0)
        #expect(RoutePlannerFilters(includedModes: []).packagePreferences.allowedModes.rawValue == 0)
    }

    @MainActor @Test func selectionsPersistIncludingEmptySelection() throws {
        let name = "RouteTransportFiltersTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("train", forKey: "AppPreferences.defaultModePreference")
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.includedRouteModes == Set(RoutePlannerFilters.selectableModes))
        preferences.includedRouteModes = [.tram, .train]
        #expect(AppPreferences(defaults: defaults).defaultRouteFilters.includedModes == [.tram, .train])
        preferences.includedRouteModes = []
        #expect(AppPreferences(defaults: defaults).includedRouteModes.isEmpty)
    }
}
