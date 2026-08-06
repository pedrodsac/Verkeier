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
            await viewModel.updateVisibleMapRegion(region, using: gtfsService)
        }
    }

    func scheduleSearchUpdate() {
        let query = viewModel.searchQuery
        guard !query.isEmpty else {
            Task {
                await viewModel.searchStops(using: gtfsService)
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

        for await query in stream.stream.debounce(for: .milliseconds(180)) {
            guard !Task.isCancelled else { return }
            guard query == viewModel.searchQuery else { continue }
            await viewModel.searchStops(using: gtfsService)
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
            await viewModel.loadNearbyStops(
                using: atpClient, location: locationService.currentLocation
            )
            await viewModel.loadNearbyStopRoutes(using: gtfsService)
        }
    }

    var sheetActions: TransitSheetActions {
        TransitSheetActions(
            selectStop: selectStop,
            showHome: showHome,
            showSearch: showSearch,
            showAlerts: showAlerts,
            showStopDetail: showStopDetail,
            showDirections: showDirections,
            showRouteOptions: showRouteOptions,
            showLineDetail: showLineDetail,
            selectLineDetailDirection: selectLineDetailDirection,
            showSettings: showSettings,
            toggleFavourite: toggleSelectedFavourite,
            refreshDepartures: refreshDepartures,
            refreshAlerts: refreshAlerts,
            calculateRoute: calculateRoute,
            selectRouteOption: selectRouteOption,
            showMoreRouteOptions: showMoreRouteOptions,
            openRouteInAppleMaps: openRouteInAppleMaps,
            selectRouteOrigin: selectRouteOrigin,
            selectRouteDestination: selectRouteDestination,
            applyCommutePreset: applyCommutePreset,
            saveCurrentCommutePreset: saveCurrentCommutePreset,
            swapRouteEndpoints: swapRouteEndpoints,
            updateRouteFilters: updateRouteFilters,
            setRoutePlanningTime: setRoutePlanningTime,
            startTrackingDeparture: startTrackingDeparture,
            stopTrackingDeparture: stopTrackingDeparture,
            scheduleDepartureReminder: scheduleDepartureReminder,
            cancelDepartureReminder: cancelDepartureReminder,
            toggleDepartureLine: toggleDepartureLine,
            selectDeparturePlatform: selectDeparturePlatform,
            updateSearch: updateSearch,
            checkGTFSUpdate: checkGTFSUpdate,
            setDebugDataMode: setDebugDataMode,
            setMapModeFilter: setMapModeFilter
        )
    }

    func setMapModeFilter(_ mode: TransportMode?) {
        animateSheetChange {
            viewModel.setMapModeFilter(mode)
        }
    }

    func selectStop(_ stop: Stop) {
        animateSheetChange {
            viewModel.selectStop(stop)
        }
        Task {
            await viewModel.updateSelectedStopRoutes(using: gtfsService)
            await viewModel.loadOfflineScheduledDepartures(using: gtfsService)
            await viewModel.loadGTFSMapStops(using: gtfsService, location: locationService.currentLocation)
        }
    }

    func selectStopGroup(_ stops: [Stop], _ bikeShareStations: [BikeShareStation]) {
        animateSheetChange {
            viewModel.selectStopGroup(stops, bikeShareStations: bikeShareStations)
        }
    }

    func showHome() {
        animateSheetChange {
            viewModel.showHome()
        }
    }

    func showSearch() {
        animateSheetChange {
            viewModel.showSearch()
        }
    }

    func showAlerts() {
        animateSheetChange {
            viewModel.showAlerts()
        }
    }

    func showStopDetail() {
        animateSheetChange {
            viewModel.showStopDetail()
        }
    }

    func showDirections() {
        animateSheetChange {
            viewModel.showDirections()
        }
        calculateRoute()
    }

    func showRouteOptions() {
        animateSheetChange {
            viewModel.showDirections()
        }
    }

    func showLineDetail(_ route: TransitRoute) {
        animateSheetChange {
            viewModel.showLineDetail(route)
        }
        Task {
            await viewModel.loadLineDetail(using: gtfsService)
        }
    }

    func selectLineDetailDirection(_ directionID: String) {
        viewModel.selectLineDetailDirection(directionID)
        Task {
            await viewModel.loadLineDetail(using: gtfsService)
        }
    }

    func selectRouteOrigin(_ place: RoutePlace?) {
        animateSheetChange {
            viewModel.selectRouteOrigin(place)
        }
    }

    func selectRouteDestination(_ place: RoutePlace) {
        animateSheetChange {
            viewModel.selectRouteDestination(place)
            if let stop = stopForRoutePlace(place) {
                viewModel.selectedStop = stop
            }
            viewModel.showDirections()
        }
    }

    func applyCommutePreset(_ presetID: String) {
        animateSheetChange {
            viewModel.applyCommutePreset(presetID)
            if let destination = viewModel.routeDestination,
               let stop = stopForRoutePlace(destination) {
                viewModel.selectedStop = stop
            }
            viewModel.showDirections()
        }
    }

    func saveCurrentCommutePreset(_ title: String) {
        viewModel.saveCurrentCommutePreset(title: title)
    }

    func swapRouteEndpoints() {
        animateSheetChange {
            viewModel.swapRouteEndpoints()
        }
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        viewModel.updateRouteFilters(filters)
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard viewModel.routePlanningTime != time else { return }
        viewModel.routePlanningTime = time
        // Re-query the service: a new time means different departures.
        calculateRoute()
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        viewModel.toggleDepartureLine(route)
    }

    func selectDeparturePlatform(_ platform: String?) {
        viewModel.selectDeparturePlatform(platform)
    }

    func showSettings() {
        animateSheetChange {
            viewModel.showSettings()
        }
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

    func requestLocation() {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationService.currentLocation == nil {
                shouldCenterOnNextLocation = true
                locationService.startUpdatingIfAllowed()
            } else {
                viewModel.centerOnUserLocation(locationService.currentLocation)
                Task {
                    await viewModel.loadGTFSMapStops(
                        using: gtfsService, location: locationService.currentLocation
                    )
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
        await viewModel.loadDepartures(using: atpClient)
        await updateTrackedDepartureIfNeeded()
    }

    func updateSearch() {
        Task {
            await viewModel.searchStops(using: gtfsService)
        }
    }

    func checkGTFSUpdate() {
        gtfsUpdateController.checkManually()
    }

    func setDebugDataMode(_ mode: DebugTransitDataMode) {
        debugTransitDataModeRawValue = mode.rawValue
        Task {
            await viewModel.loadNearbyStops(using: atpClient, location: locationService.currentLocation)
            await viewModel.loadNearbyStopRoutes(using: gtfsService)
            await loadAlertsAndCheckDisruptions()
            await viewModel.loadFavouriteDepartures(using: atpClient, favourites: favouriteStops)
            if viewModel.selectedStop != nil {
                await viewModel.loadDepartures(using: atpClient)
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

    func selectRouteOption(_ id: String) {
        animateSheetChange {
            if viewModel.selectRouteOption(id: id) {
                viewModel.showRouteTimeline()
            }
        }
    }

    func showMoreRouteOptions() {
        viewModel.showMoreRouteOptions()
    }

    func refreshAlerts() {
        Task {
            await loadAlertsAndCheckDisruptions()
        }
    }

    func loadAlertsAndCheckDisruptions() async {
        await viewModel.loadAlerts(using: avlClient)
        await viewModel.checkDisruptionAlerts(
            using: gtfsService,
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
