import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class TransitMapViewModel {
    var cameraRegion: MKCoordinateRegion
    var cameraUpdateToken = 0
    var sheetContext: TransitSheetContext = .home
    var sheetDetent: BottomSheetDetent = .medium
    var nearbyStops: [Stop] = []
    var gtfsMapStops: [Stop] = []
    var selectedStop: Stop?
    var selectedStopRoutes: [TransitRoute] = []
    var isLoadingNearbyStops = false
    var nearbyStopsErrorMessage: String?
    var departures: [Departure] = []
    var isLoadingDepartures = false
    var departuresErrorMessage: String?
    var departuresLastUpdated: Date?
    var favouriteDeparturesByStopId: [String: [Departure]] = [:]
    var isLoadingFavouriteDepartures = false
    var favouriteDeparturesErrorMessage: String?
    var favouriteDeparturesLastUpdated: Date?
    var expandedFavouriteStopIds: Set<String> = []
    var searchQuery = ""
    var searchResults: [Stop] = []
    var routePlan: RoutePlan?
    var mapRoute: MKRoute?
    var isCalculatingRoute = false
    var routeErrorMessage: String?
    var alerts: [AlertMessage] = []
    var isLoadingAlerts = false
    var alertsErrorMessage: String?
    var alertsLastUpdated: Date?

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.6116, longitude: 6.1319),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )
    private let minimumMapSpan = 0.001
    private var visibleMapRegion: MKCoordinateRegion?

    init() {
        cameraRegion = defaultRegion
    }

    func requestLocation(using locationService: LocationService) {
        locationService.requestWhenInUseAuthorization()
    }

    func showHome() {
        sheetContext = .home
        sheetDetent = .medium
        clearRoute()
    }

    func showSearch() {
        sheetContext = .search
        sheetDetent = .expanded
        clearRoute()
    }

    func showAlerts() {
        sheetContext = .alerts
        sheetDetent = .expanded
        clearRoute()
    }

    func showStopDetail() {
        guard selectedStop != nil else {
            showHome()
            return
        }
        sheetContext = .stopDetail
        sheetDetent = .medium
    }

    func showSettings() {
        sheetContext = .settings
        sheetDetent = .expanded
        clearRoute()
    }

    func showDirections() {
        guard selectedStop != nil else { return }
        sheetContext = .directions
        sheetDetent = .medium
    }

    func toggleFavouriteExpansion(stopId: String) {
        if expandedFavouriteStopIds.contains(stopId) {
            expandedFavouriteStopIds.remove(stopId)
        } else {
            expandedFavouriteStopIds.insert(stopId)
        }
    }

    func loadNearbyStops(using atpClient: any ATPClient, location: CLLocation?) async {
        isLoadingNearbyStops = true
        nearbyStopsErrorMessage = nil

        let coordinate = location?.coordinate ?? defaultRegion.center

        do {
            nearbyStops = try await atpClient.nearbyStops(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            nearbyStops = []
            nearbyStopsErrorMessage = "Nearby stops could not be loaded."
        }

        isLoadingNearbyStops = false
    }

    func loadGTFSMapStops(using gtfsService: any GTFSService, location _: CLLocation?) {
        let region = visibleMapRegion ?? cameraRegion
        loadGTFSMapStops(using: gtfsService, region: region)
    }

    func updateVisibleMapRegion(_ region: MKCoordinateRegion, using gtfsService: any GTFSService) {
        guard let region = sanitized(region) else { return }
        visibleMapRegion = region
        loadGTFSMapStops(using: gtfsService, region: region)
    }

    private func loadGTFSMapStops(using gtfsService: any GTFSService, region: MKCoordinateRegion) {
        guard let region = sanitized(region) else { return }
        let coordinate = region.center
        let center = LocationPoint(
            name: "Visible map center",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        gtfsMapStops = gtfsService.stopsForMap(
            center: center,
            latitudeDelta: max(region.span.latitudeDelta, defaultRegion.span.latitudeDelta),
            longitudeDelta: max(region.span.longitudeDelta, defaultRegion.span.longitudeDelta),
            limit: 180
        )
    }

    private func sanitized(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
        let latitude = region.center.latitude
        let longitude = region.center.longitude
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta

        guard latitude.isFinite,
            longitude.isFinite,
            latitudeDelta.isFinite,
            longitudeDelta.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            latitudeDelta > 0,
            longitudeDelta > 0
        else {
            return nil
        }

        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latitudeDelta, minimumMapSpan), 2.0),
                longitudeDelta: min(max(longitudeDelta, minimumMapSpan), 2.0)
            )
        )
    }

    func loadFavouriteDepartures(using atpClient: any ATPClient, favourites: [Stop]) async {
        guard !favourites.isEmpty else {
            favouriteDeparturesByStopId = [:]
            favouriteDeparturesErrorMessage = nil
            favouriteDeparturesLastUpdated = nil
            isLoadingFavouriteDepartures = false
            return
        }

        isLoadingFavouriteDepartures = true
        favouriteDeparturesErrorMessage = nil

        var boards: [String: [Departure]] = [:]
        var failedCount = 0

        for stop in favourites.prefix(6) {
            do {
                boards[stop.id] = try await atpClient.departureBoard(stopId: stop.id)
            } catch {
                failedCount += 1
                boards[stop.id] = []
            }
        }

        favouriteDeparturesByStopId = boards
        favouriteDeparturesLastUpdated = .now
        favouriteDeparturesErrorMessage =
            failedCount == favourites.prefix(6).count
            ? "Favourite departures could not be loaded." : nil
        isLoadingFavouriteDepartures = false
    }

    func selectStop(_ stop: Stop) {
        selectedStop = stop
        selectedStopRoutes = []
        departures = []
        departuresErrorMessage = nil
        departuresLastUpdated = nil
        routeErrorMessage = nil
        clearRoute()
        sheetContext = .stopDetail
        sheetDetent = .medium
        moveCamera(to: MKCoordinateRegion(
            center: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func loadDepartures(using atpClient: any ATPClient) async {
        guard let selectedStop else { return }
        isLoadingDepartures = true
        departuresErrorMessage = nil

        do {
            departures = try await atpClient.departureBoard(stopId: selectedStop.id)
            departuresLastUpdated = .now
        } catch {
            departures = []
            departuresErrorMessage = "Departures could not be loaded."
        }

        isLoadingDepartures = false
    }

    func searchStops(using gtfsService: any GTFSService) {
        searchResults = Array(gtfsService.searchStops(query: searchQuery).prefix(80))
    }

    func updateSelectedStopRoutes(using gtfsService: any GTFSService) {
        guard let selectedStop else {
            selectedStopRoutes = []
            return
        }

        let directRoutes = gtfsService.routesForStop(id: selectedStop.id)
        if !directRoutes.isEmpty {
            selectedStopRoutes = directRoutes
            return
        }

        selectedStopRoutes =
            gtfsService.searchStops(query: selectedStop.name)
            .filter { $0.name.normalizedForSearch == selectedStop.name.normalizedForSearch }
            .sorted {
                squaredDistance(from: $0.location, to: selectedStop.location)
                    < squaredDistance(from: $1.location, to: selectedStop.location)
            }
            .lazy
            .map { gtfsService.routesForStop(id: $0.id) }
            .first { !$0.isEmpty } ?? []
    }

    func calculateRoute(using routeService: any RouteService, from location: CLLocation?) async {
        guard let selectedStop else {
            routeErrorMessage = "Choose a destination stop first."
            return
        }
        guard let location else {
            routeErrorMessage = "Current location is required to calculate a route."
            return
        }

        isCalculatingRoute = true
        routeErrorMessage = nil
        sheetContext = .directions

        let origin = LocationPoint(
            name: "Current Location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        do {
            let calculation = try await routeService.calculateRoute(
                from: origin, to: selectedStop.location)
            routePlan = calculation.plan
            mapRoute = calculation.mapRoute
        } catch {
            routePlan = nil
            mapRoute = nil
            routeErrorMessage = "A route could not be calculated."
        }

        isCalculatingRoute = false
    }

    func openSelectedRouteInAppleMaps(
        using routeService: any RouteService, from location: CLLocation?
    ) {
        guard let selectedStop, let location else { return }
        let origin = LocationPoint(
            name: "Current Location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        routeService.openInAppleMaps(from: origin, to: selectedStop.location)
    }

    func loadAlerts(using avlClient: any AVLClient) async {
        isLoadingAlerts = true
        alertsErrorMessage = nil

        do {
            alerts = try await avlClient.fetchMessages()
            alertsLastUpdated = .now
        } catch {
            alerts = []
            alertsErrorMessage = "AVL alerts could not be loaded."
        }

        isLoadingAlerts = false
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        guard let favouriteDeparturesLastUpdated else { return false }
        return Date().timeIntervalSince(favouriteDeparturesLastUpdated) > 90
    }

    var areAlertsStale: Bool {
        guard let alertsLastUpdated else { return false }
        return Date().timeIntervalSince(alertsLastUpdated) > 300
    }

    var activeAlertCount: Int {
        alerts.count
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }

    private func clearRoute() {
        routePlan = nil
        mapRoute = nil
        routeErrorMessage = nil
        isCalculatingRoute = false
    }

    private func squaredDistance(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }

    private func moveCamera(to region: MKCoordinateRegion) {
        guard let region = sanitized(region) else { return }
        cameraRegion = region
        visibleMapRegion = region
        cameraUpdateToken += 1
    }
}
