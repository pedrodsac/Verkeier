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
            calculateRoute: router.calculateRoute,
            refreshRouteRealtime: refreshSelectedRouteRealtime,
            showDirections: router.showDirections,
            showHome: router.showHome,
            openSpecialEvent: openSpecialEvent,
            expandSheet: router.expand,
            openRouteInAppleMaps: openRouteInAppleMaps,
            selectRouteOrigin: router.selectRouteOrigin,
            selectRouteDestination: router.selectRouteDestination,
            applyCommutePreset: router.applyCommutePreset,
            applyAndCalculatePreset: router.applyAndCalculatePreset,
            saveCurrentCommutePreset: saveCurrentCommutePreset,
            swapRouteEndpoints: router.swapRouteEndpoints,
            showRoutePlaceSearch: router.showRoutePlaceSearch,
            updateRouteFilters: router.updateRouteFilters,
            setRoutePlanningTime: router.setRoutePlanningTime,
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
                openStop: { router.show([.stopDetail($0)], detent: .medium) },
                planTo: router.planRoute(to:),
                planFrom: router.planRoute(from:),
                refreshStop: refreshFavouriteStop,
                refreshAll: refreshFavouriteStops,
                updateLabels: updateFavouriteLabels,
                updateAppearance: updateFavouriteAppearance,
                removeFavourite: removeFavourite,
                findStop: router.showSearch
            ),
            openDepartureTrip: { departure, stop, selection in
                router.openTrip(selection, replacing: departure, at: stop)
            },
            refreshTripDetail: { await tripDetailViewModel.refresh(using: tripDetailService) },
            refreshRoutes: router.refreshRoutes,
            maintainRoutes: router.maintainRoutes
        )
    }

    func openSpecialEvent(_ event: SpecialEvent) {
        Task { @MainActor in
            _ = event
        }
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

    func saveCurrentCommutePreset(_ title: String) {
        routePlanner.saveCurrentCommutePreset(title: title)
    }

    func selectLineDetailDirection(_ directionID: String) {
        lineDetail.selectLineDetailDirection(directionID)
        Task {
            await lineDetail.loadLineDetail(using: gtfsService)
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

    func openRouteInAppleMaps() {
        routePlanner.openSelectedRouteInAppleMaps(
            using: routeService,
            from: locationService.currentLocation
        )
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
