import Foundation
import Testing
@testable import Verkeier

struct RoutePlannerStoreTests {
    private func makeStore() -> (RoutePlannerStore, UserDefaults) {
        // A throwaway in-memory-ish suite per test; cleared up front.
        let suite = "RoutePlannerStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (RoutePlannerStore(defaults: defaults), defaults)
    }

    private func place(_ id: String, source: RoutePlaceSource = .search) -> RoutePlace {
        RoutePlace(
            id: id,
            title: id,
            location: LocationPoint(id: id, latitude: 49.6, longitude: 6.1),
            source: source
        )
    }

    @Test func recordRecentPlaceDedupesAndCaps() {
        let (store, _) = makeStore()
        for index in 0 ..< 12 {
            _ = store.recordRecentPlace(place("p\(index)"))
        }
        _ = store.recordRecentPlace(place("p0")) // re-add an old one → moves to front
        let recents = store.recentPlaces()
        #expect(recents.count <= 8)
        #expect(recents.first?.id == "p0")
        #expect(Set(recents.map(\.id)).count == recents.count) // no duplicates
    }

    @Test func currentLocationPlacesAreNotRecorded() {
        let (store, _) = makeStore()
        _ = store.recordRecentPlace(place("here", source: .currentLocation))
        #expect(store.recentPlaces().isEmpty)
    }

    @Test func recentStopsDeduplicateCrossFeedCopies() {
        let (store, _) = makeStore()
        let atpStop = Stop(
            id: "atp-hamilius",
            name: "Hamilius (Bus)",
            location: LocationPoint(latitude: 49.6110, longitude: 6.1260),
            modes: [.bus],
            dataSource: .atpOpenAPI
        )
        let gtfsStop = Stop(
            id: "gtfs-hamilius",
            name: "Hamilius (Bus)",
            location: LocationPoint(latitude: 49.6114, longitude: 6.1261),
            modes: [.bus],
            dataSource: .gtfs
        )

        _ = store.recordRecentStop(atpStop)
        _ = store.recordRecentStop(gtfsStop)

        #expect(store.recentStops().map(\.id) == ["gtfs-hamilius"])
    }

    @Test func recentTripsDedupeByEndpointsAndCapAtTen() {
        let (store, _) = makeStore()
        for index in 0 ..< 12 {
            _ = store.recordRecentTrip(origin: place("o"), destination: place("d\(index)"))
        }
        _ = store.recordRecentTrip(origin: place("o"), destination: place("d0"))
        let trips = store.recentTrips()
        #expect(trips.count <= 10)
        #expect(trips.first?.destination.id == "d0")
    }

    @Test func clearAllRemovesEverything() {
        let (store, _) = makeStore()
        _ = store.recordRecentPlace(place("p"))
        _ = store.recordRecentTrip(origin: place("o"), destination: place("d"))
        store.saveCommutePresets([
            RouteCommutePreset(title: "Home → Work", origin: place("o"), destination: place("d"))
        ])
        store.clearAll()
        #expect(store.recentPlaces().isEmpty)
        #expect(store.recentTrips().isEmpty)
        #expect(store.commutePresets().isEmpty)
    }
}
