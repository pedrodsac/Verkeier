import CoreLocation
import SwiftUI

/// The bottom sheet's navigation, and the flows that span several features.
///
/// Screens navigate and start cross-feature work, such as opening a stop or
/// showing directions, through the router instead of receiving closures. The
/// feature models stay independent of each other: only the router changes more
/// than one of them.
@MainActor @Observable
final class SheetRouter {
    var selectedTab: TransitSheetTab = .home
    var homePath: [TransitSheetRoute] = []
    var planPath: [TransitSheetRoute] = []
    var detent: BottomSheetDetent = .medium
    /// Mirrors the scene phase so background work pauses while the app is inactive.
    var isSceneActive = true

    @ObservationIgnored let models: FeatureModels
    @ObservationIgnored let locationService: LocationService
    @ObservationIgnored private let routeService: any RouteService
    @ObservationIgnored private let gtfsService: any GTFSService

    init(
        models: FeatureModels,
        locationService: LocationService,
        routeService: any RouteService,
        gtfsService: any GTFSService
    ) {
        self.models = models
        self.locationService = locationService
        self.routeService = routeService
        self.gtfsService = gtfsService
    }

    var activePath: [TransitSheetRoute] {
        switch selectedTab {
        case .home: homePath
        case .plan: planPath
        case .settings: []
        }
    }
}

// MARK: - Navigation

extension SheetRouter {
    /// Replaces the Home path with `routes`.
    func show(_ routes: [TransitSheetRoute], detent: BottomSheetDetent? = nil) {
        animate {
            selectedTab = .home
            homePath = routes
            self.detent = detent ?? routes.last?.defaultDetent ?? .medium
        }
    }

    func showHome() {
        animate {
            selectedTab = .home
            homePath = []
            detent = .medium
            models.map.clearStopGroup()
            models.routePlanner.clearRoute()
            models.lineDetail.clearLineDetail()
        }
    }

    func showPlanTab() {
        animate {
            selectedTab = .plan
            planPath = []
            detent = .medium
        }
    }

    func showSearch() {
        models.routePlanner.clearRoute()
        models.lineDetail.clearLineDetail()
        show([.search], detent: .expanded)
    }

    func showAlerts() {
        models.routePlanner.clearRoute()
        show([.alerts], detent: .expanded)
    }

    func showRoutePlaceSearch(_ endpoint: RouteEndpoint) {
        animate {
            selectedTab = .plan
            planPath.append(.routePlaceSearch(endpoint))
            detent = .expanded
        }
    }

    func expand() {
        animate {
            detent = .expanded
        }
    }

    /// Swaps the "loading this run" placeholder for the resolved trip.
    func openTrip(_ selection: TripDetailSelection, replacing departure: Departure, at stop: Stop) {
        guard activePath.last == .departureTrip(departure, stop) else { return }
        switch selectedTab {
        case .home: homePath[homePath.count - 1] = .tripDetail(selection)
        case .plan: planPath[planPath.count - 1] = .tripDetail(selection)
        case .settings: break
        }
    }

    private func animate(_ changes: () -> Void) {
        if let animation = Animation.respectingReduceMotion(
            .snappy(duration: 0.28),
            UIAccessibility.isReduceMotionEnabled
        ) {
            withAnimation(animation) { changes() }
        } else {
            changes()
        }
    }
}

// MARK: - Route activation

extension SheetRouter {
    /// Prepares the feature models for the route a navigation stack just
    /// showed. Going back never reloads the screen underneath.
    func pathDidChange(from previous: [TransitSheetRoute], to path: [TransitSheetRoute]) {
        guard path != previous else { return }
        let isBackNavigation =
            path.count < previous.count
            && Array(previous.prefix(path.count)) == path
        guard !isBackNavigation, let route = path.last else { return }

        switch route {
        case .search, .stopGroup, .routePlaceSearch, .alerts, .tripDetail, .departureTrip:
            break

        case let .stopDetail(stop):
            let cameFromLineDetail =
                if case .lineDetail = previous.last { true } else { false }
            selectStop(stop, preservingLineDetail: cameFromLineDetail)
            Task { await models.map.loadGTFSMapStops(using: gtfsService) }

        case .directions:
            calculateRoute()

        case let .directionsForPreset(presetID):
            applyCommutePreset(presetID)
            calculateRoute()

        case let .routeTimeline(optionID):
            models.routePlanner.selectRouteOption(id: optionID)

        case let .lineDetail(route):
            let lineDetail = models.lineDetail
            if lineDetail.prepareLineDetail(route) || lineDetail.selectedLineDetail == nil {
                Task { await lineDetail.loadLineDetail(using: gtfsService) }
            }
        }
    }
}

// MARK: - Stops

extension SheetRouter {
    /// Shows `stop` across the feature models: its departure board, a route to
    /// it, and the map moved to it.
    func selectStop(_ stop: Stop, preservingLineDetail: Bool = false) {
        models.map.clearStopGroup()
        models.stopDetail.select(stop)
        models.search.recordRecentStop(stop)
        models.routePlanner.planToSelectedStop(stop)
        if !preservingLineDetail {
            models.lineDetail.clearLineDetail()
        }
        models.map.focus(on: stop.location.coordinate)
    }

    /// Opens a tapped map cluster: a single stop directly, or the group.
    func openStopGroup(_ stops: [Stop], bikeShareStations: [BikeShareStation]) {
        switch models.map.selectStopGroup(stops, bikeShareStations: bikeShareStations) {
        case .group:
            models.stopDetail.clearSelection()
            models.routePlanner.clearEndpoints()
            models.lineDetail.clearLineDetail()
        case let .singleStop(stop):
            selectStop(stop)
        case .none:
            break
        }
        if let selectedStop = models.stopDetail.selectedStop {
            show([.stopDetail(selectedStop)])
        } else {
            show([.stopGroup])
        }
    }
}

// MARK: - Route planning

extension SheetRouter {
    func showDirections() {
        showPlanTab()
        calculateRoute()
    }

    func planRoute(to stop: Stop) {
        selectRouteDestination(RoutePlace(stop: stop, source: .favourite))
        showPlanTab()
    }

    func planRoute(from stop: Stop) {
        selectRouteOrigin(RoutePlace(stop: stop, source: .favourite))
        showPlanTab()
    }

    func selectRouteOrigin(_ place: RoutePlace?) {
        models.routePlanner.selectRouteOrigin(place)
    }

    func selectRouteDestination(_ place: RoutePlace) {
        models.routePlanner.selectRouteDestination(place)
        if let stop = knownStop(for: place) {
            models.stopDetail.selectedStop = stop
        }
    }

    func applyCommutePreset(_ presetID: String) {
        models.routePlanner.applyCommutePreset(presetID)
        if let destination = models.routePlanner.routeDestination,
            let stop = knownStop(for: destination)
        {
            models.stopDetail.selectedStop = stop
        }
    }

    func applyAndCalculatePreset(_ presetID: String) {
        applyCommutePreset(presetID)
        calculateRoute()
    }

    func swapRouteEndpoints() {
        let currentLocation = locationService.currentLocation.map { location in
            RoutePlace.currentLocation(
                LocationPoint(
                    name: "Current Location",
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )
        }
        animate {
            models.routePlanner.swapRouteEndpoints(currentLocation: currentLocation)
        }
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        models.routePlanner.updateRouteFilters(filters)
        if hasRouteEndpoint {
            calculateRoute()
        }
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard models.routePlanner.routePlanningTime != time else { return }
        models.routePlanner.setRoutePlanningTime(time)
        // A future time can be picked before an endpoint exists. In that case
        // remember it without surfacing a destination error.
        if hasRouteEndpoint {
            calculateRoute()
        }
    }

    /// Calculates routes, asking for the rider's location first when the trip
    /// starts from it.
    func calculateRoute() {
        let routePlanner = models.routePlanner
        if routePlanner.routeOrigin == nil, locationService.currentLocation == nil {
            switch locationService.authorizationStatus {
            case .denied, .restricted:
                routePlanner.failRouteLocationRequest()
                return
            default:
                break
            }

            requestLocation()
        }

        let refresh: RouteRealtimeRefreshPolicy = routePlanner.routeOptions.isEmpty ? .useCache : .forceRefresh
        Task {
            await routePlanner.calculateRoute(
                using: routeService,
                from: locationService.currentLocation,
                realtimeRefreshPolicy: refresh
            )
        }
    }

    /// Pull to refresh on the route results.
    func refreshRoutes() async {
        let routePlanner = models.routePlanner
        guard routePlanner.routeDestination != nil else { return }
        guard routePlanner.routeOrigin != nil || locationService.currentLocation != nil else {
            calculateRoute()
            return
        }
        await routePlanner.refreshRoutes(using: routeService, from: locationService.currentLocation)
    }

    /// Keeps "leave now" results current while the route screen is visible.
    func maintainRoutes() async {
        guard models.routePlanner.routeDestination != nil else { return }
        if models.routePlanner.routeOptions.isEmpty {
            await refreshRoutesIfIdle()
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard !Task.isCancelled else { return }
            if isSceneActive {
                await refreshRoutesIfIdle()
            }
        }
    }

    /// Finishes a calculation that was waiting for the first location fix.
    func calculateWaitingRouteIfNeeded() {
        guard models.routePlanner.isWaitingForRouteLocation, locationService.currentLocation != nil else {
            return
        }
        calculateRoute()
    }

    private var hasRouteEndpoint: Bool {
        models.routePlanner.routeDestination != nil || models.stopDetail.selectedStop != nil
    }

    private func refreshRoutesIfIdle() async {
        let routePlanner = models.routePlanner
        guard routePlanner.routeDestination != nil,
            routePlanner.routeRefreshTask == nil,
            !routePlanner.isCalculatingRoute,
            !routePlanner.isLoadingEarlierRoutes, !routePlanner.isLoadingLaterRoutes,
            // Browsed pages stay until the user pulls to refresh.
            !routePlanner.isBrowsingRoutePages
        else { return }
        guard routePlanner.routeOrigin != nil || locationService.currentLocation != nil else {
            calculateRoute()
            return
        }
        await routePlanner.calculateRoute(
            using: routeService,
            from: locationService.currentLocation,
            realtimeRefreshPolicy: .forceRefresh
        )
    }

    /// The full stop behind `place`, when the app already knows it.
    private func knownStop(for place: RoutePlace) -> Stop? {
        guard let stopId = place.stopId else { return nil }
        if let favourite = models.favourites.favouriteStops.first(where: { $0.id == stopId }) {
            return favourite
        }
        if let nearby = models.map.nearbyStops.first(where: { $0.id == stopId }) {
            return nearby
        }
        if let result = models.search.searchResults.first(where: { $0.id == stopId }) {
            return result
        }
        if let selectedStop = models.stopDetail.selectedStop, selectedStop.id == stopId {
            return selectedStop
        }
        return nil
    }
}

// MARK: - Location

extension SheetRouter {
    /// Centers the map on the rider, asking for permission or a first fix when
    /// needed.
    func requestLocation() {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationService.currentLocation == nil {
                models.map.centersOnNextLocation = true
                locationService.startUpdatingIfAllowed()
            } else {
                models.map.centerOnUserLocation(locationService.currentLocation)
                Task { await models.map.loadGTFSMapStops(using: gtfsService) }
            }
        case .notDetermined:
            models.map.centersOnNextLocation = true
            locationService.requestWhenInUseAuthorization()
        default:
            locationService.requestWhenInUseAuthorization()
        }
    }
}
