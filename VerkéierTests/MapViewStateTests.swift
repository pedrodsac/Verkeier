import MapKit
import Testing
@testable import Verkeier

@MainActor
struct MapViewStateTests {
    @Test func unchangedMapInputsSkipUpdates() {
        #expect(state() == state())
    }

    @Test func changesToExistingStopAreNotHiddenByStableIDs() {
        let old = stop(name: "Central", latitude: 49.61, modes: [.bus])
        #expect(state(stops: [old]) != state(stops: [stop(name: "Gare", latitude: 49.61, modes: [.bus])]))
        #expect(state(stops: [old]) != state(stops: [stop(name: "Central", latitude: 49.62, modes: [.bus])]))
        #expect(state(stops: [old]) != state(stops: [stop(name: "Central", latitude: 49.61, modes: [.tram])]))
    }

    @Test func viewportChangesDoNotBecomeCameraCommands() {
        #expect(state(latitude: 49.61) == state(latitude: 49.62))
        #expect(state(token: 0) != state(token: 1))
    }

    @Test func pinAppearanceAndVisibilityTriggerUpdates() {
        #expect(state() != state(selectedID: "stop"))
        #expect(state() != state(favourites: ["stop"]))
        #expect(state() != state(alerts: ["stop"]))
        #expect(state() != state(hidden: true))
    }

    @Test func sameTransferIDCanMoveOrChangeTitle() {
        func overlay(_ title: String, _ latitude: Double) -> RouteMapOverlay {
            RouteMapOverlay(segments: [], transferMarkers: [RouteTransferMarker(
                id: "transfer", title: title,
                coordinate: RouteMapCoordinate(latitude: latitude, longitude: 6.13)
            )])
        }
        #expect(state(overlay: overlay("Gare", 49.61)) != state(overlay: overlay("Central", 49.61)))
        #expect(state(overlay: overlay("Gare", 49.61)) != state(overlay: overlay("Gare", 49.62)))
    }

    @Test func changedStopRetainsAnnotationIdentityAndUpdatesItsPayload() {
        let annotation = StopMapAnnotation(stop: stop(name: "Central", latitude: 49.61, modes: [.bus]), layer: .gtfs)
        let key = annotation.key
        var coordinateChanges = 0
        let observation = annotation.observe(\.coordinate) { _, _ in coordinateChanges += 1 }
        let changed = stop(name: "Gare", latitude: 49.62, modes: [.tram])
        annotation.update(stop: changed)
        annotation.update(stop: changed)
        #expect(annotation.key == key)
        #expect(annotation.title == "Gare")
        #expect(annotation.coordinate.latitude == 49.62)
        #expect(annotation.stop.modes == [.tram])
        #expect(coordinateChanges == 1)
        observation.invalidate()
    }

    private func stop(name: String, latitude: Double, modes: [TransportMode]) -> Stop {
        Stop(id: "stop", name: name, location: LocationPoint(latitude: latitude, longitude: 6.13),
             modes: modes, dataSource: .mock)
    }

    private func state(
        stops: [Stop] = [], latitude: Double = 49.61, token: Int = 0,
        selectedID: String? = nil, favourites: Set<String> = [], alerts: Set<String> = [],
        hidden: Bool = false, overlay: RouteMapOverlay? = nil
    ) -> MapViewState {
        MapViewState(
            region: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: 6.13),
                                       span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
            cameraUpdateToken: token, liveStops: [], gtfsStops: stops,
            selectedStopId: selectedID, favouriteStopIds: favourites, alertStopIds: alerts,
            bikeShareStations: [], routeOverlay: overlay, hideMapPins: hidden
        )
    }
}
