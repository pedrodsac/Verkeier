import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func requestLocation(using locationService: LocationService) {
        locationService.requestWhenInUseAuthorization()
    }

    func loadNearbyStops(location: CLLocation?, force: Bool = false) async {
        let requestLocation = location ?? CLLocation(
            latitude: defaultRegion.center.latitude,
            longitude: defaultRegion.center.longitude
        )
        guard force || shouldRefreshNearbyStops(for: requestLocation) else { return }
        lastNearbyStopsRequestLocation = requestLocation
        isLoadingNearbyStops = true
        nearbyStops = []
        nearbyStopsErrorMessage = "Transit data is currently unavailable."

        isLoadingNearbyStops = false
    }

    func shouldRefreshNearbyStops(for location: CLLocation) -> Bool {
        guard let lastNearbyStopsRequestLocation else { return true }
        return location.distance(from: lastNearbyStopsRequestLocation) >= nearbyStopsRefreshDistance
    }

    /// Loads the lines serving each nearby stop, with bounded concurrency, so
    /// the nearby list can show "12 · 14 · 25" rather than just a mode label.
    func loadNearbyStopRoutes() async {
        nearbyStopRoutes = [:]
    }

    func loadGTFSMapStops(location _: CLLocation?) async {
        let region = visibleMapRegion ?? cameraRegion
        await loadGTFSMapStops(region: region)
    }

    func updateVisibleMapRegion(_ region: MKCoordinateRegion) async {
        guard let region = sanitized(region) else { return }
        visibleMapRegion = region
        await loadGTFSMapStops(region: region)
    }

    private func loadGTFSMapStops(region: MKCoordinateRegion) async {
        guard let region = sanitized(region) else { return }
        gtfsMapStops = []
    }

    func selectStop(
        _ stop: Stop,
        preservingLineDetail: Bool = false,
        using store: RoutePlannerStore = .shared
    ) {
        selectedStopGroup = []
        selectedBikeShareStations = []
        selectedStop = stop
        recentStops = store.recordRecentStop(stop)
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
        if !preservingLineDetail {
            clearLineDetail()
        }
        selectedStopRoutes = []
        departures = []
        offlineScheduledDepartures = []
        selectedDepartureLine = nil
        selectedDeparturePlatform = nil
        departureBoardFilter = TransitBoardFilter()
        departuresErrorMessage = nil
        departuresLastUpdated = nil
        routeErrorMessage = nil
        clearRoute()
        moveCamera(to: anchoredRegion(
            for: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func selectStopGroup(
        _ stops: [Stop],
        bikeShareStations: [BikeShareStation] = []
    ) {
        let uniqueStops = stops.deduplicatedByExactName()
        var seenBikeShareStations = Set<String>()
        let uniqueBikeShareStations = bikeShareStations.filter {
            seenBikeShareStations.insert($0.id).inserted
        }
        guard uniqueStops.count + uniqueBikeShareStations.count > 1 else {
            if let stop = uniqueStops.first {
                selectStop(stop)
            }
            return
        }

        selectedStop = nil
        selectedStopGroup = uniqueStops
        selectedBikeShareStations = uniqueBikeShareStations
        routeOrigin = nil
        routeDestination = nil
        clearLineDetail()
        clearRoute()
        if let coordinate = uniqueStops.first?.location.coordinate
            ?? uniqueBikeShareStations.first?.location.coordinate {
            moveCamera(to: anchoredRegion(
                for: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
    }

    func searchStops() async {
        let query = searchQuery
        async let mapKitLookup = Self.mapKitStops(matching: query)

        // A newer keystroke may have superseded this query while MapKit ran.
        guard query == searchQuery else { return }
        searchResults = await mapKitLookup.deduplicatedByExactName()
    }

    func updateSelectedStopRoutes() async {
        selectedStopRoutes = []
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: anchoredRegion(
            for: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }
}
