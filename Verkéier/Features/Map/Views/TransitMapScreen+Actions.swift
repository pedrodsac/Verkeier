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
            await map.updateVisibleMapRegion(region, using: gtfsService)
        }
    }

    func scheduleSearchUpdate() {
        let query = search.searchQuery
        guard !query.isEmpty else {
            Task {
                await search.searchStops(using: gtfsService)
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
            guard query == search.searchQuery else { continue }
            await search.searchStops(using: gtfsService)
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
            await map.loadNearbyStops(
                location: locationService.currentLocation,
                using: liveTransitService,
                gtfsService: gtfsService,
                walkingRouter: walkingRouter
            )
            await map.loadNearbyStopRoutes(using: gtfsService)
        }
    }

    var sheetActions: TransitSheetActions {
        TransitSheetActions(
            toggleFavourite: toggleSelectedFavourite,
            saveFavouriteCustomization: { stop, label, colorHex, iconName in
                saveFavouriteCustomization(
                    stop: stop,
                    label: label,
                    colorHex: colorHex,
                    iconName: iconName
                )
            },
            refreshDepartures: refreshDepartures,
            refreshAlerts: refreshAlerts,
            calculateRoute: calculateRoute,
            refreshRouteRealtime: refreshSelectedRouteRealtime,
            showDirections: showDirections,
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
            updateSearch: updateSearch,
            selectLineDetailDirection: selectLineDetailDirection,
            refreshLineDetail: refreshLineDetail,
            favourites: FavouritesActions(
                openStop: openFavouriteStop,
                planTo: planToFavouriteStop,
                planFrom: planFromFavouriteStop,
                refreshStop: refreshFavouriteStop,
                refreshAll: refreshFavouriteStops,
                updateLabels: updateFavouriteLabels,
                updateAppearance: updateFavouriteAppearance,
                removeFavourite: removeFavourite,
                findStop: showSearch
            ),
            openDepartureTrip: { departure, stop, selection in
                guard sheetNavigation.activePath.last == .departureTrip(departure, stop) else { return }
                switch sheetNavigation.selectedTab {
                case .home: sheetNavigation.homePath[sheetNavigation.homePath.count - 1] = .tripDetail(selection)
                case .plan: sheetNavigation.planPath[sheetNavigation.planPath.count - 1] = .tripDetail(selection)
                case .settings: break
                }
            },
            refreshTripDetail: { await tripDetailViewModel.refresh(using: tripDetailService) },
            refreshRoutes: refreshRoutes,
            maintainRoutes: maintainRoutes
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
        navigateToSheet([.stopDetail(stop)], detent: .medium)
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

    func showDirections() {
        showPlanTab()
        calculateRoute()
    }

    func refreshFavouriteStop(_ stop: Stop) async {
        await favourites.refreshFavouriteDeparture(
            stop: stop,
            using: liveTransitService,
            gtfsService: gtfsService
        )
    }

    func refreshFavouriteStops() async {
        await favourites.loadFavouriteDepartures(
            favourites: favouriteStops,
            using: liveTransitService,
            gtfsService: gtfsService
        )
    }

    func updateFavouriteLabels(stopID: String, labels: [String]) {
        guard let favourite = favouriteEntities.first(where: { $0.stopId == stopID }) else { return }
        favourite.replaceLabels(with: labels)
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    func updateFavouriteAppearance(stopID: String, label: String, colorHex: String, iconName: String) {
        guard let favourite = favouriteEntities.first(where: { $0.stopId == stopID }) else { return }
        favourite.displayLabel = label
        favourite.colorHex = colorHex
        favourite.iconName = iconName
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    func removeFavourite(stopID: String) {
        guard let favourite = favouriteEntities.first(where: { $0.stopId == stopID }) else { return }
        modelContext.delete(favourite)
        favourites.removeBoard(forStopID: stopID)
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    /// Shows `stop` across the feature models: its departure board, a route to
    /// it, and the map moved to it.
    func applyStopSelection(_ stop: Stop, preservingLineDetail: Bool = false) {
        map.clearStopGroup()
        stopDetail.select(stop)
        search.recordRecentStop(stop)
        routePlanner.planToSelectedStop(stop)
        if !preservingLineDetail {
            lineDetail.clearLineDetail()
        }
        map.focus(on: stop.location.coordinate)
    }

    func selectStopGroup(_ stops: [Stop], _ bikeShareStations: [BikeShareStation]) {
        switch map.selectStopGroup(stops, bikeShareStations: bikeShareStations) {
        case .group:
            stopDetail.clearSelection()
            routePlanner.clearEndpoints()
            lineDetail.clearLineDetail()
        case let .singleStop(stop):
            applyStopSelection(stop)
        case .none:
            break
        }
        if let selectedStop = stopDetail.selectedStop {
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
            map.clearStopGroup()
            routePlanner.clearRoute()
            lineDetail.clearLineDetail()
        }
    }

    func expandSheet() {
        animateSheetChange {
            sheetDetent = .expanded
        }
    }

    func showSearch() {
        routePlanner.clearRoute()
        lineDetail.clearLineDetail()
        navigateToSheet([.search], detent: .expanded)
    }

    func showAlerts() {
        routePlanner.clearRoute()
        navigateToSheet([.alerts], detent: .expanded)
    }

    func selectLineDetailDirection(_ directionID: String) {
        lineDetail.selectLineDetailDirection(directionID)
        Task {
            await lineDetail.loadLineDetail(using: gtfsService)
        }
    }

    func selectRouteOrigin(_ place: RoutePlace?) {
        routePlanner.selectRouteOrigin(place)
    }

    func selectRouteDestination(_ place: RoutePlace) {
        routePlanner.selectRouteDestination(place)
        if let stop = stopForRoutePlace(place) {
            stopDetail.selectedStop = stop
        }
    }

    func applyCommutePreset(_ presetID: String) {
        routePlanner.applyCommutePreset(presetID)
        if let destination = routePlanner.routeDestination,
            let stop = stopForRoutePlace(destination)
        {
            stopDetail.selectedStop = stop
        }
    }

    func applyAndCalculatePreset(_ presetID: String) {
        applyCommutePreset(presetID)
        calculateRoute()
    }

    func saveCurrentCommutePreset(_ title: String) {
        routePlanner.saveCurrentCommutePreset(title: title)
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
        animateSheetChange {
            routePlanner.swapRouteEndpoints(currentLocation: currentLocation)
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
        routePlanner.updateRouteFilters(filters)
        if routePlanner.routeDestination != nil || stopDetail.selectedStop != nil {
            calculateRoute()
        }
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard routePlanner.routePlanningTime != time else { return }
        routePlanner.setRoutePlanningTime(time)
        // A future time can be picked before an endpoint exists. In that case
        // remember it without surfacing a destination error.
        if routePlanner.routeDestination != nil || stopDetail.selectedStop != nil {
            calculateRoute()
        }
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        stopDetail.toggleDepartureLine(route)
        Task { await stopDetail.loadDepartures(using: liveTransitService, gtfsService: gtfsService) }
    }

    func selectDeparturePlatform(_ platform: String?) {
        stopDetail.selectDeparturePlatform(platform)
        Task { await stopDetail.loadDepartures(using: liveTransitService, gtfsService: gtfsService) }
    }

    func stopForRoutePlace(_ place: RoutePlace) -> Stop? {
        if let stopId = place.stopId {
            if let favourite = favouriteStops.first(where: { $0.id == stopId }) {
                return favourite
            }
            if let nearby = map.nearbyStops.first(where: { $0.id == stopId }) {
                return nearby
            }
            if let result = search.searchResults.first(where: { $0.id == stopId }) {
                return result
            }
            if let selectedStop = stopDetail.selectedStop, selectedStop.id == stopId {
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
                applyStopSelection(stop, preservingLineDetail: preservesLineDetail)
            },
            loadSelectedStopData: loadSelectedStopData,
            calculateRoute: calculateRoute,
            applyCommutePreset: applyCommutePreset,
            selectRouteOption: { optionID in
                _ = routePlanner.selectRouteOption(id: optionID)
            },
            prepareLineDetail: { lineDetail.prepareLineDetail($0) || lineDetail.selectedLineDetail == nil },
            loadLineDetail: {
                Task {
                    await lineDetail.loadLineDetail(using: gtfsService)
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
            await map.loadGTFSMapStops(using: gtfsService)
        }
    }

    func requestLocation() {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationService.currentLocation == nil {
                shouldCenterOnNextLocation = true
                locationService.startUpdatingIfAllowed()
            } else {
                map.centerOnUserLocation(locationService.currentLocation)
                Task {
                    await map.loadGTFSMapStops(using: gtfsService)
                }
            }
        case .notDetermined:
            shouldCenterOnNextLocation = true
            locationService.requestWhenInUseAuthorization()
        default:
            locationService.requestWhenInUseAuthorization()
        }
    }

    func refreshDepartures() async {
        await stopDetail.loadDepartures(using: liveTransitService, gtfsService: gtfsService)
        await updateTrackedDepartureIfNeeded()
    }

    func updateSearch() {
        Task {
            await search.searchStops(using: gtfsService)
        }
    }

    func refreshLineDetail() async {
        favourites.gtfsFeedStatus = await gtfsService.refreshIfNeeded(force: true)
        await lineDetail.loadLineDetail(using: gtfsService)
    }

    func calculateRoute() {
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

    func refreshRoutes() async {
        guard routePlanner.routeDestination != nil else { return }
        guard routePlanner.routeOrigin != nil || locationService.currentLocation != nil else {
            calculateRoute()
            return
        }
        await routePlanner.refreshRoutes(using: routeService, from: locationService.currentLocation)
    }

    private func refreshRoutesIfIdle() async {
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

    func maintainRoutes() async {
        guard routePlanner.routeDestination != nil else { return }
        if routePlanner.routeOptions.isEmpty {
            await refreshRoutesIfIdle()
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard !Task.isCancelled else { return }
            if scenePhase == .active {
                await refreshRoutesIfIdle()
            }
        }
    }

    func refreshSelectedRouteRealtime() async {
        await routePlanner.refreshSelectedRouteRealtime(using: routeService)
    }

    func loadEarlierRoutes() {
        Task {
            await routePlanner.loadEarlierRoutes(
                using: routeService,
                from: locationService.currentLocation
            )
        }
    }

    func loadLaterRoutes() {
        Task {
            await routePlanner.loadLaterRoutes(
                using: routeService,
                from: locationService.currentLocation
            )
        }
    }

    func calculateWaitingRouteIfNeeded() {
        guard routePlanner.isWaitingForRouteLocation, locationService.currentLocation != nil else {
            return
        }

        calculateRoute()
    }

    func openRouteInAppleMaps() {
        routePlanner.openSelectedRouteInAppleMaps(
            using: routeService,
            from: locationService.currentLocation
        )
    }

    func refreshAlerts() {
        Task {
            await loadAlertsAndCheckDisruptions()
        }
    }

    func loadAlertsAndCheckDisruptions() async {
        await alerts.loadAlerts(using: avlClient)
        await alerts.checkDisruptionAlerts(disruptionAlertService: disruptionAlertService)
    }

    func startTrackingDeparture(_ departure: Departure) {
        guard let selectedStop = stopDetail.selectedStop else { return }
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
        guard let selectedStop = stopDetail.selectedStop else { return }
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
