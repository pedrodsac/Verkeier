import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    func scheduleMapRegionUpdate(_ region: MKCoordinateRegion) {
        mapRegionUpdateTask?.cancel()
        mapRegionUpdateTask = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.updateVisibleMapRegion(region)
        }
    }

    func scheduleSearchUpdate() {
        let query = viewModel.searchQuery
        guard !query.isEmpty else {
            Task {
                await viewModel.searchStops()
            }
            return
        }
        searchUpdateContinuation?.yield(query)
    }

    func observeSearchUpdates() async {
        let stream = AsyncStream<String>.makeStream(of: String.self)
        searchUpdateContinuation = stream.continuation
        defer {
            searchUpdateContinuation = nil
        }

        for await query in stream.stream.debounce(for: .milliseconds(250)) {
            guard !Task.isCancelled else { return }
            guard query == viewModel.searchQuery else { continue }
            await viewModel.searchStops()
        }
    }

    func scheduleNearbyStopsRefresh() {
        nearbyStopsUpdateTask?.cancel()
        nearbyStopsUpdateTask = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.loadNearbyStops(location: locationService.currentLocation)
            await viewModel.loadNearbyStopRoutes()
        }
    }

    var sheetActions: TransitSheetActions {
        TransitSheetActions(
            toggleFavourite: toggleSelectedFavourite,
            refreshDepartures: refreshDepartures,
            refreshAlerts: refreshAlerts,
            calculateRoute: calculateRoute,
            showHome: showHome,
            openSpecialEvent: openSpecialEvent,
            expandSheet: expandSheet,
            openRouteInAppleMaps: openRouteInAppleMaps,
            selectRouteOrigin: selectRouteOrigin,
            selectRouteDestination: selectRouteDestination,
            applyCommutePreset: applyCommutePreset,
            applyAndCalculatePreset: applyAndCalculatePreset,
            saveCurrentCommutePreset: saveCurrentCommutePreset,
            swapRouteEndpoints: swapRouteEndpoints,
            showRoutePlaceSearch: showRoutePlaceSearch,
            updateRouteFilters: updateRouteFilters,
            setRoutePlanningTime: setRoutePlanningTime,
            loadEarlierRoutes: loadEarlierRoutes,
            loadLaterRoutes: loadLaterRoutes,
            startTrackingDeparture: startTrackingDeparture,
            stopTrackingDeparture: stopTrackingDeparture,
            scheduleDepartureReminder: scheduleDepartureReminder,
            cancelDepartureReminder: cancelDepartureReminder,
            toggleDepartureLine: toggleDepartureLine,
            selectDeparturePlatform: selectDeparturePlatform,
            updateDepartureBoardFilter: updateDepartureBoardFilter,
            updateSearch: updateSearch,
            selectLineDetailDirection: selectLineDetailDirection,
            checkGTFSUpdate: checkGTFSUpdate,
            setDebugDataMode: setDebugDataMode,
            favourites: FavouritesActions(
                openStop: openFavouriteStop,
                planTo: planToFavouriteStop,
                planFrom: planFromFavouriteStop,
                refreshStop: refreshFavouriteStop,
                refreshAll: refreshFavouriteStops,
                updateLabels: updateFavouriteLabels,
                removeFavourite: removeFavourite,
                findStop: showSearch
            )
        )
    }

    func selectStop(_ stop: Stop) {
        navigateToSheet([.stopDetail(stop)])
    }

    func openSpecialEvent(_ event: SpecialEvent) {
        Task { @MainActor in
            _ = event
        }
    }

    func openFavouriteStop(_ stop: Stop) {
        animateSheetChange {
            sheetNavigation.selectedTab = .favourites
            sheetNavigation.favouritesPath.append(.stopDetail(stop))
            sheetDetent = .medium
        }
    }

    func planToFavouriteStop(_ stop: Stop) {
        selectRouteDestination(RoutePlace(stop: stop, source: .favourite))
        showPlanTab()
    }

    func planFromFavouriteStop(_ stop: Stop) {
        selectRouteOrigin(RoutePlace(stop: stop, source: .favourite))
        showPlanTab()
    }

    func showPlanTab() {
        animateSheetChange {
            sheetNavigation.selectedTab = .plan
            sheetNavigation.planPath = []
            sheetDetent = .medium
        }
    }

    func refreshFavouriteStop(_ stop: Stop) async {
        viewModel.markFavouriteDeparturesUnavailable(for: [stop])
    }

    func refreshFavouriteStops() async {
        await viewModel.loadFavouriteDepartures(favourites: favouriteStops)
    }

    func updateFavouriteLabels(stopID: String, labels: [String]) {
        guard let favourite = favouriteEntities.first(where: { $0.stopId == stopID }) else { return }
        favourite.replaceLabels(with: labels)
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    func removeFavourite(stopID: String) {
        guard let favourite = favouriteEntities.first(where: { $0.stopId == stopID }) else { return }
        modelContext.delete(favourite)
        viewModel.favouriteDepartureBoards.removeValue(forKey: stopID)
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    func selectStopGroup(_ stops: [Stop], _ bikeShareStations: [BikeShareStation]) {
        viewModel.selectStopGroup(stops, bikeShareStations: bikeShareStations)
        if let selectedStop = viewModel.selectedStop {
            navigateToSheet([.stopDetail(selectedStop)])
        } else {
            navigateToSheet([.stopGroup])
        }
    }

    func showHome() {
        animateSheetChange {
            sheetNavigation.selectedTab = .home
            sheetNavigation.homePath = []
            sheetDetent = .medium
            viewModel.selectedStopGroup = []
            viewModel.selectedBikeShareStations = []
            viewModel.clearRoute()
            viewModel.clearLineDetail()
        }
    }

    func expandSheet() {
        animateSheetChange {
            sheetDetent = .expanded
        }
    }

    func showSearch() {
        viewModel.clearRoute()
        viewModel.clearLineDetail()
        navigateToSheet([.search], detent: .expanded)
    }

    func showAlerts() {
        viewModel.clearRoute()
        navigateToSheet([.alerts], detent: .expanded)
    }

    func selectLineDetailDirection(_ directionID: String) {
        viewModel.selectLineDetailDirection(directionID)
        Task {
            await viewModel.loadLineDetail()
        }
    }

    func selectRouteOrigin(_ place: RoutePlace?) {
        viewModel.selectRouteOrigin(place)
    }

    func selectRouteDestination(_ place: RoutePlace) {
        viewModel.selectRouteDestination(place)
        if let stop = stopForRoutePlace(place) {
            viewModel.selectedStop = stop
        }
    }

    func applyCommutePreset(_ presetID: String) {
        viewModel.applyCommutePreset(presetID)
        if let destination = viewModel.routeDestination,
           let stop = stopForRoutePlace(destination) {
            viewModel.selectedStop = stop
        }
    }

    func applyAndCalculatePreset(_ presetID: String) {
        applyCommutePreset(presetID)
        calculateRoute()
    }

    func saveCurrentCommutePreset(_ title: String) {
        viewModel.saveCurrentCommutePreset(title: title)
    }

    func swapRouteEndpoints() {
        animateSheetChange {
            viewModel.swapRouteEndpoints()
        }
    }

    func showRoutePlaceSearch(_ endpoint: RouteEndpoint) {
        animateSheetChange {
            sheetNavigation.selectedTab = .plan
            sheetNavigation.planPath.append(.routePlaceSearch(endpoint))
            sheetDetent = .expanded
        }
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        viewModel.updateRouteFilters(filters)
        if viewModel.routeDestination != nil || viewModel.selectedStop != nil {
            calculateRoute()
        }
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard viewModel.routePlanningTime != time else { return }
        viewModel.setRoutePlanningTime(time)
        // A future time can be picked before an endpoint exists. In that case
        // remember it without surfacing a destination error.
        if viewModel.routeDestination != nil || viewModel.selectedStop != nil {
            calculateRoute()
        }
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        viewModel.toggleDepartureLine(route)
        Task { await viewModel.loadDepartures() }
    }

    func selectDeparturePlatform(_ platform: String?) {
        viewModel.selectDeparturePlatform(platform)
        Task { await viewModel.loadDepartures() }
    }

    func updateDepartureBoardFilter(_ filter: TransitBoardFilter) {
        viewModel.updateDepartureBoardFilter(filter)
        Task { await viewModel.loadDepartures() }
    }

    func stopForRoutePlace(_ place: RoutePlace) -> Stop? {
        if let stopId = place.stopId {
            if let favourite = favouriteStops.first(where: { $0.id == stopId }) {
                return favourite
            }
            if let nearby = viewModel.nearbyStops.first(where: { $0.id == stopId }) {
                return nearby
            }
            if let result = viewModel.searchResults.first(where: { $0.id == stopId }) {
                return result
            }
            if let selectedStop = viewModel.selectedStop, selectedStop.id == stopId {
                return selectedStop
            }
        }
        return nil
    }

    func animateSheetChange(_ changes: () -> Void) {
        if let animation = Animation.respectingReduceMotion(.snappy(duration: 0.28), reduceMotion) {
            withAnimation(animation) { changes() }
        } else {
            changes()
        }
    }

    func navigateToSheet(
        _ routes: [TransitSheetRoute],
        detent: BottomSheetDetent? = nil
    ) {
        animateSheetChange {
            sheetNavigation.selectedTab = .home
            sheetNavigation.homePath = routes
            sheetDetent = detent ?? routes.last?.defaultDetent ?? .medium
        }
    }

    func navigateToSheet(
        _ route: TransitSheetRoute,
        reset: Bool = true,
        detent: BottomSheetDetent? = nil
    ) {
        let routes = reset ? [route] : sheetNavigation.homePath + [route]
        navigateToSheet(routes, detent: detent)
    }

    func activateSheetRoute(
        _ route: TransitSheetRoute?,
        _ previousRoute: TransitSheetRoute?,
        _ isBackNavigation: Bool
    ) {
        TransitSheetRouteActivationCoordinator(
            selectStop: { stop, preservesLineDetail in
                viewModel.selectStop(stop, preservingLineDetail: preservesLineDetail)
            },
            loadSelectedStopData: loadSelectedStopData,
            calculateRoute: calculateRoute,
            applyCommutePreset: applyCommutePreset,
            selectRouteOption: { optionID in
                _ = viewModel.selectRouteOption(id: optionID)
            },
            prepareLineDetail: { viewModel.prepareLineDetail($0) || viewModel.selectedLineDetail == nil },
            loadLineDetail: {
                Task {
                    await viewModel.loadLineDetail()
                }
            }
        )
        .activate(
            route,
            previousRoute: previousRoute,
            isBackNavigation: isBackNavigation
        )
    }

    func loadSelectedStopData() {
        Task {
            await viewModel.updateSelectedStopRoutes()
            await viewModel.loadOfflineScheduledDepartures()
            await viewModel.loadGTFSMapStops(location: locationService.currentLocation)
        }
    }

    func requestLocation() {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationService.currentLocation == nil {
                shouldCenterOnNextLocation = true
                locationService.startUpdatingIfAllowed()
            } else {
                viewModel.centerOnUserLocation(locationService.currentLocation)
                Task {
                    await viewModel.loadGTFSMapStops(location: locationService.currentLocation)
                }
            }
        case .notDetermined:
            shouldCenterOnNextLocation = true
            viewModel.requestLocation(using: locationService)
        default:
            viewModel.requestLocation(using: locationService)
        }
    }

    func refreshDepartures() async {
        await viewModel.loadDepartures()
        await updateTrackedDepartureIfNeeded()
    }

    func updateSearch() {
        Task {
            await viewModel.searchStops()
        }
    }

    func checkGTFSUpdate() {
        // GTFS updates are intentionally disconnected.
    }

    func setDebugDataMode(_ mode: DebugTransitDataMode) {
        debugTransitDataModeRawValue = mode.rawValue
        Task {
            await loadAlertsAndCheckDisruptions()
            await refreshFavouriteStops()
            if viewModel.selectedStop != nil {
                await viewModel.loadDepartures()
            }
        }
    }

    func calculateRoute() {
        if locationService.currentLocation == nil {
            switch locationService.authorizationStatus {
            case .denied, .restricted:
                viewModel.failRouteLocationRequest()
                return
            default:
                break
            }

            requestLocation()
        }

        Task {
            await viewModel.calculateRoute(
                using: routeService, from: locationService.currentLocation
            )
        }
    }

    func loadEarlierRoutes() {
        Task {
            await viewModel.loadEarlierRoutes(
                using: routeService, from: locationService.currentLocation
            )
        }
    }

    func loadLaterRoutes() {
        Task {
            await viewModel.loadLaterRoutes(
                using: routeService, from: locationService.currentLocation
            )
        }
    }

    func calculateWaitingRouteIfNeeded() {
        guard viewModel.isWaitingForRouteLocation, locationService.currentLocation != nil else {
            return
        }

        calculateRoute()
    }

    func openRouteInAppleMaps() {
        viewModel.openSelectedRouteInAppleMaps(
            using: routeService, from: locationService.currentLocation
        )
    }

    func refreshAlerts() {
        Task {
            await loadAlertsAndCheckDisruptions()
        }
    }

    func loadAlertsAndCheckDisruptions() async {
        await viewModel.loadAlerts(using: avlClient)
        await viewModel.checkDisruptionAlerts(
            disruptionAlertService: disruptionAlertService,
            favouriteStops: favouriteStops
        )
    }

    func startTrackingDeparture(_ departure: Departure) {
        guard let selectedStop = viewModel.selectedStop else { return }
        Task {
            await liveActivityManager.startTracking(departure: departure, stop: selectedStop)
        }
    }

    func stopTrackingDeparture() {
        Task {
            await liveActivityManager.endTracking()
        }
    }

    func scheduleDepartureReminder(_ departure: Departure, _ leadTimeMinutes: Int) {
        guard let selectedStop = viewModel.selectedStop else { return }
        Task {
            await departureReminderService.scheduleReminder(
                for: departure,
                stop: selectedStop,
                leadTimeMinutes: leadTimeMinutes
            )
        }
    }

    func cancelDepartureReminder() {
        departureReminderService.cancelReminder()
    }

}
