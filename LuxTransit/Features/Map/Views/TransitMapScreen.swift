import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

struct TransitMapScreen: View {
    @AppStorage("debugTransitDataMode") private var debugTransitDataModeRawValue =
        DebugTransitDataMode.normal.rawValue
    @Environment(\.atpClient) private var atpClient
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.gtfsUpdateController) private var gtfsUpdateController
    @Environment(\.routeService) private var routeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.avlClient) private var avlClient
    @Environment(\.liveActivityManager) private var liveActivityManager
    @Environment(\.departureReminderService) private var departureReminderService
    @Environment(\.disruptionAlertService) private var disruptionAlertService
    @Environment(\.appConfiguration) private var appConfiguration
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) private var favouriteEntities:
        [PersistedFavouriteStop]
    @State private var viewModel = TransitMapViewModel()
    @State private var mapRegionUpdateTask: Task<Void, Never>?
    @State private var searchUpdateContinuation: AsyncStream<String>.Continuation?
    @State private var nearbyStopsUpdateTask: Task<Void, Never>?
    @State private var shouldCenterOnNextLocation = false
    @State private var isMainSheetPresented = true
    @State private var favouriteStopIds: Set<String> = []
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let locationService: LocationService

    var body: some View {
        ZStack(alignment: .bottom) {
            map

            VStack {
                HStack {
                    Spacer()
                    LocationPermissionButton(
                        authorizationStatus: locationService.authorizationStatus,
                        requestLocation: requestLocation
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $isMainSheetPresented) {
            TransitBottomSheet(
                searchQuery: $viewModel.searchQuery,
                detent: viewModel.sheetDetent,
                viewModel: sheetPresentationModel,
                actions: sheetActions
            )
            .presentationDetents(
                BottomSheetDetent.presentationDetents,
                selection: sheetPresentationDetent
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .presentationBackgroundInteraction(
                .enabled(upThrough: BottomSheetDetent.mediumPresentationDetent)
            )
            .presentationCornerRadius(28)
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: .init(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            FirstRunOnboardingView(readiness: settingsReadinessSnapshot) {
                hasCompletedOnboarding = true
                gtfsUpdateController.checkAutomatically()
            }
        }
        .onChange(of: isMainSheetPresented) {
            if !isMainSheetPresented {
                isMainSheetPresented = true
            }
        }
        .task {
            viewModel.loadRoutePlanner()
            locationService.startUpdatingIfAllowed()
            await viewModel.loadGTFSMapStops(
                using: gtfsService, location: locationService.currentLocation
            )
            await viewModel.loadNearbyStops(
                using: atpClient, location: locationService.currentLocation
            )
            await viewModel.loadNearbyStopRoutes(using: gtfsService)
            await loadAlertsAndCheckDisruptions()
            await viewModel.loadFavouriteDepartures(using: atpClient, favourites: favouriteStops)
            gtfsUpdateController.loadSnapshot()
            gtfsUpdateController.checkAutomatically()
        }
        .task {
            await observeSearchUpdates()
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedStop?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: favouriteStopIds.count)
        .onChange(of: locationService.currentLocation) {
            if shouldCenterOnNextLocation, locationService.currentLocation != nil {
                viewModel.centerOnUserLocation(locationService.currentLocation)
                shouldCenterOnNextLocation = false
            }
            Task {
                await viewModel.loadGTFSMapStops(
                    using: gtfsService, location: locationService.currentLocation
                )
            }
            scheduleNearbyStopsRefresh()
            calculateWaitingRouteIfNeeded()
        }
        .task(id: departureRefreshKey) {
            guard viewModel.selectedStop != nil, viewModel.sheetContext == .stopDetail else {
                return
            }
            await viewModel.loadDepartures(using: atpClient)
            await updateTrackedDepartureIfNeeded()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                await viewModel.loadDepartures(using: atpClient)
                await updateTrackedDepartureIfNeeded()
            }
        }
        .task(id: favouriteRefreshKey) {
            await viewModel.loadFavouriteDepartures(using: atpClient, favourites: favouriteStops)
        }
        .onChange(of: viewModel.searchQuery) {
            scheduleSearchUpdate()
        }
        .onChange(of: favouriteEntities) {
            favouriteStopIds = Set(favouriteEntities.map(\.stopId))
            mirrorFavouriteEntitiesForIntents()
        }
        .onAppear {
            favouriteStopIds = Set(favouriteEntities.map(\.stopId))
            mirrorFavouriteEntitiesForIntents()
            handlePendingIntentHandoff()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            handlePendingIntentHandoff()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            handleSpotlightActivity(activity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gtfsDidUpdate)) { _ in
            Task {
                await viewModel.loadGTFSMapStops(
                    using: gtfsService, location: locationService.currentLocation
                )
                await viewModel.updateSelectedStopRoutes(using: gtfsService)
                await viewModel.loadOfflineScheduledDepartures(using: gtfsService)
                await viewModel.searchStops(using: gtfsService)
                if viewModel.selectedLineDetailRoute != nil {
                    await viewModel.loadLineDetail(using: gtfsService)
                }
            }
        }
    }

    private var map: some View {
        TransitMapView(
            region: viewModel.cameraRegion,
            cameraUpdateToken: viewModel.cameraUpdateToken,
            liveStops: stopsForMode(viewModel.nearbyStops),
            gtfsStops: stopsForMode(viewModel.gtfsOnlyMapStops),
            selectedStopId: viewModel.selectedStop?.id,
            favouriteStopIds: favouriteStopIds,
            alertStopIds: Set(viewModel.alerts.flatMap(\.affectedStopIds)),
            routeOverlay: viewModel.activeMapOverlay,
            selectStop: selectStop,
            regionDidChange: scheduleMapRegionUpdate
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            MapModeFilterBar(selected: viewModel.mapModeFilter, select: setMapModeFilter)
                // Sit just above the collapsed sheet edge (collapsed detent = 70pt).
                .padding(.bottom, 82)
        }
        .accessibilityLabel("Luxembourg transit map")
    }

    private func stopsForMode(_ stops: [Stop]) -> [Stop] {
        guard let mode = viewModel.mapModeFilter else { return stops }
        return stops.filter { $0.modes.contains(mode) }
    }

    private var favouriteStops: [Stop] {
        favouriteEntities.map(\.stop)
    }

    private var favouriteRefreshKey: String {
        favouriteEntities.map(\.stopId).joined(separator: "|")
    }

    private var departureRefreshKey: String {
        "\(viewModel.selectedStop?.id ?? "none")|\(viewModel.sheetContext)"
    }

    private var sheetPresentationModel: TransitSheetPresentationModel {
        let nearby = NearbyStopsPresentationModel(
            stops: viewModel.nearbyStops,
            isLoading: viewModel.isLoadingNearbyStops,
            errorMessage: viewModel.nearbyStopsErrorMessage,
            referenceLocation: locationService.currentLocation,
            routesByStopId: viewModel.nearbyStopRoutes
        )

        return TransitSheetPresentationModel(
            context: viewModel.sheetContext,
            nearby: nearby,
            commute: CommuteDashboardViewModel(
                favourites: favouriteStops,
                departuresByStopId: viewModel.favouriteDeparturesByStopId,
                isLoadingDepartures: viewModel.isLoadingFavouriteDepartures,
                errorMessage: viewModel.favouriteDeparturesErrorMessage,
                lastUpdated: viewModel.favouriteDeparturesLastUpdated,
                isStale: viewModel.areFavouriteDeparturesStale,
                expandedStopIds: viewModel.expandedFavouriteStopIds,
                nearby: nearby,
                activeAlertCount: viewModel.activeAlertCount,
                suggestedCommutePreset: viewModel.suggestedCommutePreset,
                recentStops: viewModel.recentStops
            ),
            search: SearchPresentationModel(
                results: viewModel.searchResults,
                nearbySuggestions: viewModel.nearbyStops,
                isLoadingNearbySuggestions: viewModel.isLoadingNearbyStops,
                referenceLocation: locationService.currentLocation
            ),
            stopDetail: StopDetailPresentationModel(
                stop: viewModel.selectedStop,
                routes: viewModel.selectedStopRoutes,
                departures: viewModel.filteredDepartures,
                offlineScheduledDepartures: viewModel.offlineScheduledDepartures,
                alerts: viewModel.stopDetailAlerts,
                availablePlatforms: viewModel.availableDeparturePlatforms,
                selectedLine: viewModel.selectedDepartureLine,
                selectedPlatform: viewModel.selectedDeparturePlatform,
                isLoadingDepartures: viewModel.isLoadingDepartures,
                errorMessage: viewModel.departuresErrorMessage,
                lastUpdated: viewModel.departuresLastUpdated,
                isStale: viewModel.areDeparturesStale,
                isFavourite: viewModel.selectedStop.map(isFavourite) ?? false,
                trackedDepartureId: liveActivityManager.trackedDepartureId,
                liveActivityErrorMessage: liveActivityManager.lastErrorMessage,
                liveActivityStaleMessage: liveActivityManager.staleExplanation,
                activeReminder: departureReminderForSelectedStop,
                departureReminderErrorMessage: departureReminderService.lastErrorMessage
            ),
            route: RoutePresentationModel(
                selectedStop: viewModel.selectedStop,
                origin: viewModel.routeOrigin,
                destination: viewModel.routeDestination,
                favouritePlaces: favouriteStops.map { RoutePlace(stop: $0, source: .favourite) },
                nearbyPlaces: viewModel.nearbyStops.map { RoutePlace(stop: $0, source: .nearby) },
                recentPlaces: viewModel.recentRoutePlaces,
                commutePresets: viewModel.commutePresets,
                recentTrips: viewModel.recentTrips,
                filters: viewModel.routeFilters,
                planningTime: viewModel.routePlanningTime,
                routeOptions: viewModel.routeOptions,
                alerts: viewModel.routeAlerts,
                legAlerts: viewModel.routeLegAlerts,
                selectedRouteOptionID: viewModel.selectedRouteOptionID,
                visibleRouteOptionCount: viewModel.visibleRouteOptionCount,
                loadingPhase: viewModel.routeLoadingPhase,
                errorMessage: viewModel.routeErrorMessage,
                statusMessage: viewModel.routeStatusMessage
            ),
            lineDetail: LineDetailPresentationModel(
                route: viewModel.selectedLineDetailRoute,
                detail: viewModel.selectedLineDetail,
                alerts: viewModel.lineDetailAlerts,
                errorMessage: viewModel.selectedLineDetailErrorMessage
            ),
            alerts: AlertsPresentationModel(
                alerts: viewModel.alerts,
                isLoading: viewModel.isLoadingAlerts,
                errorMessage: viewModel.alertsErrorMessage,
                lastUpdated: viewModel.alertsLastUpdated,
                isStale: viewModel.areAlertsStale
            ),
            settings: SettingsPresentationModel(
                configuration: appConfiguration,
                gtfsUpdateSnapshot: gtfsUpdateController.snapshot,
                isCheckingGTFSUpdate: gtfsUpdateController.isChecking,
                readiness: settingsReadinessSnapshot,
                supportBundleText: settingsSupportBundleText,
                debugDataMode: debugTransitDataMode
            )
        )
    }

    private var settingsReadinessSnapshot: DataReadinessSnapshot {
        SettingsSupport.readinessSnapshot(
            configuration: appConfiguration,
            gtfsSnapshot: gtfsUpdateController.snapshot,
            hasBundledSeed: Bundle.main.url(forResource: "gtfs-compact", withExtension: "json") != nil
        )
    }

    private var settingsSupportBundleText: String {
        SettingsSupport.supportBundleText(
            appVersion: appVersion,
            readiness: settingsReadinessSnapshot,
            gtfsSnapshot: gtfsUpdateController.snapshot,
            configuration: appConfiguration
        )
    }

    private var appVersion: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var debugTransitDataMode: DebugTransitDataMode {
        DebugTransitDataMode(rawValue: debugTransitDataModeRawValue) ?? .normal
    }

    private var departureReminderForSelectedStop: SharedTrackedDepartureReminder? {
        guard let selectedStopID = viewModel.selectedStop?.id else { return nil }
        guard let reminder = departureReminderService.activeReminder, reminder.stopId == selectedStopID else {
            return nil
        }
        return reminder
    }

    private var sheetPresentationDetent: Binding<PresentationDetent> {
        Binding(
            get: {
                viewModel.sheetDetent.presentationDetent
            },
            set: { presentationDetent in
                viewModel.sheetDetent = BottomSheetDetent(presentationDetent: presentationDetent)
            }
        )
    }

    private func scheduleMapRegionUpdate(_ region: MKCoordinateRegion) {
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

    private func scheduleSearchUpdate() {
        let query = viewModel.searchQuery
        guard !query.isEmpty else {
            Task {
                await viewModel.searchStops(using: gtfsService)
            }
            return
        }
        searchUpdateContinuation?.yield(query)
    }

    private func observeSearchUpdates() async {
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

    private func scheduleNearbyStopsRefresh() {
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

    private var sheetActions: TransitSheetActions {
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
            toggleFavouriteExpansion: toggleFavouriteExpansion,
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

    private func setMapModeFilter(_ mode: TransportMode?) {
        animateSheetChange {
            viewModel.setMapModeFilter(mode)
        }
    }

    private func selectStop(_ stop: Stop) {
        animateSheetChange {
            viewModel.selectStop(stop)
        }
        Task {
            await viewModel.updateSelectedStopRoutes(using: gtfsService)
            await viewModel.loadOfflineScheduledDepartures(using: gtfsService)
            await viewModel.loadGTFSMapStops(using: gtfsService, location: locationService.currentLocation)
        }
    }

    private func showHome() {
        animateSheetChange {
            viewModel.showHome()
        }
    }

    private func showSearch() {
        animateSheetChange {
            viewModel.showSearch()
        }
    }

    private func showAlerts() {
        animateSheetChange {
            viewModel.showAlerts()
        }
    }

    private func showStopDetail() {
        animateSheetChange {
            viewModel.showStopDetail()
        }
    }

    private func showDirections() {
        animateSheetChange {
            viewModel.showDirections()
        }
        calculateRoute()
    }

    private func showRouteOptions() {
        animateSheetChange {
            viewModel.showDirections()
        }
    }

    private func showLineDetail(_ route: TransitRoute) {
        animateSheetChange {
            viewModel.showLineDetail(route)
        }
        Task {
            await viewModel.loadLineDetail(using: gtfsService)
        }
    }

    private func selectLineDetailDirection(_ directionID: String) {
        viewModel.selectLineDetailDirection(directionID)
        Task {
            await viewModel.loadLineDetail(using: gtfsService)
        }
    }

    private func selectRouteOrigin(_ place: RoutePlace?) {
        animateSheetChange {
            viewModel.selectRouteOrigin(place)
        }
    }

    private func selectRouteDestination(_ place: RoutePlace) {
        animateSheetChange {
            viewModel.selectRouteDestination(place)
            if let stop = stopForRoutePlace(place) {
                viewModel.selectedStop = stop
            }
            viewModel.showDirections()
        }
    }

    private func applyCommutePreset(_ presetID: String) {
        animateSheetChange {
            viewModel.applyCommutePreset(presetID)
            if let destination = viewModel.routeDestination,
               let stop = stopForRoutePlace(destination) {
                viewModel.selectedStop = stop
            }
            viewModel.showDirections()
        }
    }

    private func saveCurrentCommutePreset(_ title: String) {
        viewModel.saveCurrentCommutePreset(title: title)
    }

    private func swapRouteEndpoints() {
        animateSheetChange {
            viewModel.swapRouteEndpoints()
        }
    }

    private func updateRouteFilters(_ filters: RoutePlannerFilters) {
        viewModel.updateRouteFilters(filters)
    }

    private func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard viewModel.routePlanningTime != time else { return }
        viewModel.routePlanningTime = time
        // Re-query the service: a new time means different departures.
        calculateRoute()
    }

    private func toggleDepartureLine(_ route: TransitRoute) {
        viewModel.toggleDepartureLine(route)
    }

    private func selectDeparturePlatform(_ platform: String?) {
        viewModel.selectDeparturePlatform(platform)
    }

    private func showSettings() {
        animateSheetChange {
            viewModel.showSettings()
        }
    }

    private func toggleFavouriteExpansion(_ stopId: String) {
        animateSheetChange {
            viewModel.toggleFavouriteExpansion(stopId: stopId)
        }
    }

    private func stopForRoutePlace(_ place: RoutePlace) -> Stop? {
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

    private func animateSheetChange(_ changes: () -> Void) {
        if let animation = Animation.respectingReduceMotion(.snappy(duration: 0.28), reduceMotion) {
            withAnimation(animation) { changes() }
        } else {
            changes()
        }
    }

    private func requestLocation() {
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

    private func refreshDepartures() async {
        await viewModel.loadDepartures(using: atpClient)
        await updateTrackedDepartureIfNeeded()
    }

    private func updateSearch() {
        Task {
            await viewModel.searchStops(using: gtfsService)
        }
    }

    private func checkGTFSUpdate() {
        gtfsUpdateController.checkManually()
    }

    private func setDebugDataMode(_ mode: DebugTransitDataMode) {
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

    private func calculateRoute() {
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

    private func calculateWaitingRouteIfNeeded() {
        guard viewModel.isWaitingForRouteLocation, locationService.currentLocation != nil else {
            return
        }

        calculateRoute()
    }

    private func openRouteInAppleMaps() {
        viewModel.openSelectedRouteInAppleMaps(
            using: routeService, from: locationService.currentLocation
        )
    }

    private func selectRouteOption(_ id: String) {
        animateSheetChange {
            if viewModel.selectRouteOption(id: id) {
                viewModel.showRouteTimeline()
            }
        }
    }

    private func showMoreRouteOptions() {
        viewModel.showMoreRouteOptions()
    }

    private func refreshAlerts() {
        Task {
            await loadAlertsAndCheckDisruptions()
        }
    }

    private func loadAlertsAndCheckDisruptions() async {
        await viewModel.loadAlerts(using: avlClient)
        await viewModel.checkDisruptionAlerts(
            using: gtfsService,
            disruptionAlertService: disruptionAlertService,
            favouriteStops: favouriteStops
        )
    }

    private func startTrackingDeparture(_ departure: Departure) {
        guard let selectedStop = viewModel.selectedStop else { return }
        Task {
            await liveActivityManager.startTracking(departure: departure, stop: selectedStop)
        }
    }

    private func stopTrackingDeparture() {
        Task {
            await liveActivityManager.endTracking()
        }
    }

    private func scheduleDepartureReminder(_ departure: Departure, _ leadTimeMinutes: Int) {
        guard let selectedStop = viewModel.selectedStop else { return }
        Task {
            await departureReminderService.scheduleReminder(
                for: departure,
                stop: selectedStop,
                leadTimeMinutes: leadTimeMinutes
            )
        }
    }

    private func cancelDepartureReminder() {
        departureReminderService.cancelReminder()
    }

    private func updateTrackedDepartureIfNeeded() async {
        if let trackedDeparture = DepartureTrackingSelection.trackedDeparture(
            in: viewModel.departures,
            trackedDepartureId: liveActivityManager.trackedDepartureId
        ) {
            await liveActivityManager.updateTracking(departure: trackedDeparture)
        }

        if let reminderDepartureID = departureReminderService.activeReminder?.departureId,
           let reminderDeparture = viewModel.departures.first(where: { $0.id == reminderDepartureID }) {
            await departureReminderService.syncTrackedDeparture(
                reminderDeparture,
                stopName: viewModel.selectedStop?.name
            )
        }
    }

    private func trackNextDeparture(for stop: Stop) {
        Task {
            await viewModel.loadDepartures(using: atpClient)
            guard let departure = DepartureTrackingSelection.nextTrackableDeparture(
                from: viewModel.departures
            ) else {
                return
            }
            await liveActivityManager.startTracking(departure: departure, stop: stop)
        }
    }

    private func isFavourite(_ stop: Stop) -> Bool {
        favouriteEntities.contains { $0.stopId == stop.id }
    }

    private func toggleSelectedFavourite() {
        guard let selectedStop = viewModel.selectedStop else { return }

        if let existing = favouriteEntities.first(where: { $0.stopId == selectedStop.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(PersistedFavouriteStop(stop: selectedStop))
        }

        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
    }

    private func mirrorFavouriteEntitiesForIntents() {
        let stops = favouriteStops
        FavouriteStopEntityStore.save(stops: stops)
        if stops.isEmpty {
            FavouriteStopSpotlightIndexer.removeAll()
        } else {
            FavouriteStopSpotlightIndexer.index(stops)
        }
    }

    private func handlePendingIntentHandoff() {
        guard let handoff = TransitIntentHandoff.consumePending() else { return }
        handle(handoff)
    }

    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("stop.")
        else {
            return
        }

        let stopId = String(identifier.dropFirst("stop.".count))
        guard let stop = favouriteEntities.first(where: { $0.stopId == stopId })?.stop else {
            viewModel.showSearch()
            return
        }

        selectStop(stop)
        viewModel.sheetDetent = .expanded
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = TransitDeepLink(url: url),
              let handoff = TransitIntentHandoff(deepLink)
        else {
            return
        }

        handle(handoff)
    }

    private func handle(_ handoff: TransitIntentHandoff) {
        switch handoff {
        case .showNearbyStops:
            viewModel.showHome()
        case let .openFavouriteStop(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                viewModel.selectStop(favourite)
                Task {
                    await viewModel.updateSelectedStopRoutes(using: gtfsService)
                    await viewModel.loadOfflineScheduledDepartures(using: gtfsService)
                }
                viewModel.sheetDetent = .expanded
            } else {
                viewModel.showSearch()
            }
        case let .trackNextDeparture(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                viewModel.selectStop(favourite)
                Task {
                    await viewModel.updateSelectedStopRoutes(using: gtfsService)
                    await viewModel.loadOfflineScheduledDepartures(using: gtfsService)
                }
                viewModel.sheetDetent = .expanded
                trackNextDeparture(for: favourite)
            } else {
                viewModel.showSearch()
            }
        case let .planRoute(destinationName):
            viewModel.searchQuery = destinationName
            Task {
                await viewModel.searchStops(using: gtfsService)
                if let stop = confidentRouteDestinationMatch(for: destinationName) {
                    selectStop(stop)
                    showDirections()
                } else {
                    viewModel.showSearch()
                }
            }
        }
    }

    private func confidentRouteDestinationMatch(for destinationName: String) -> Stop? {
        let normalizedDestination = destinationName.normalizedForSearch
        let exactMatches = viewModel.searchResults.filter {
            $0.name.normalizedForSearch == normalizedDestination
        }

        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        return viewModel.searchResults.count == 1 ? viewModel.searchResults[0] : nil
    }
}



#Preview {
    TransitMapScreen(locationService: LocationService())
}
