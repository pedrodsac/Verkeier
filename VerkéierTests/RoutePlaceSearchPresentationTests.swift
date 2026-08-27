import Testing

@testable import Verkeier

struct RoutePlaceSearchPresentationTests {
    @Test func destinationPinsSelectedStopBeforeRecentsAndDeduplicatesIt() {
        let selectedStop = Stop(
            id: "selected-stop",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(id: "selected-stop", latitude: 49.611, longitude: 6.126),
            modes: [.bus],
            dataSource: .gtfs
        )
        let currentLocation = RoutePlace.currentLocation(
            LocationPoint(id: "current", latitude: 49.61, longitude: 6.13)
        )
        let duplicateSelectedPlace = RoutePlace(stop: selectedStop, source: .recent)
        let recentPlace = RoutePlace(
            id: "recent-place",
            title: "Kirchberg",
            location: LocationPoint(id: "recent-place", latitude: 49.63, longitude: 6.17),
            source: .recent
        )

        let model = RoutePresentationModel(
            selectedStop: selectedStop,
            origin: nil,
            destination: nil,
            currentLocation: currentLocation,
            favouritePlaces: [],
            nearbyPlaces: [],
            recentPlaces: [duplicateSelectedPlace, recentPlace],
            commutePresets: [],
            filters: RoutePlannerFilters(),
            planningTime: .leaveNow,
            routeOptions: [],
            alerts: [],
            selectedRouteOptionID: nil,
            loadingPhase: .idle,
            errorMessage: nil,
            statusMessage: nil
        )

        #expect(model.selectedPlace(for: .destination)?.id == selectedStop.id)
        #expect(model.recentPlacesExcludingPinned(for: .destination).map(\.id) == [recentPlace.id])
    }
}
