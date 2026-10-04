import MapKit

/// The data the map renders from, bundled so the call site passes one value
/// instead of eight positional arguments.
struct MapViewState: Equatable {
    let region: MKCoordinateRegion
    let cameraUpdateToken: Int
    let liveStops: [Stop]
    let gtfsStops: [Stop]
    let selectedStopId: String?
    let favouriteStopIds: Set<String>
    let alertStopIds: Set<String>
    let bikeShareStations: [BikeShareStation]
    let routeOverlay: RouteMapOverlay?
    let hideMapPins: Bool

    /// The token owns camera commands. Reading a viewport must not recenter it.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cameraUpdateToken == rhs.cameraUpdateToken
            && lhs.liveStops == rhs.liveStops
            && lhs.gtfsStops == rhs.gtfsStops
            && lhs.selectedStopId == rhs.selectedStopId
            && lhs.favouriteStopIds == rhs.favouriteStopIds
            && lhs.alertStopIds == rhs.alertStopIds
            && lhs.bikeShareStations == rhs.bikeShareStations
            && lhs.routeOverlay == rhs.routeOverlay
            && lhs.hideMapPins == rhs.hideMapPins
    }
}
