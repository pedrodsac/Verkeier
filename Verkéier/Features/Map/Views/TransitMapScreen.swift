import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

struct TransitMapScreen: View {
    @AppStorage("debugTransitDataMode") var debugTransitDataModeRawValue =
        DebugTransitDataMode.normal.rawValue
    @Environment(\.atpClient) var atpClient
    @Environment(\.gtfsService) var gtfsService
    @Environment(\.gtfsUpdateController) var gtfsUpdateController
    @Environment(\.routeService) var routeService
    @Environment(\.bikeShareService) private var bikeShareService
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.avlClient) var avlClient
    @Environment(\.liveActivityManager) var liveActivityManager
    @Environment(\.departureReminderService) var departureReminderService
    @Environment(\.disruptionAlertService) var disruptionAlertService
    @Environment(\.appConfiguration) var appConfiguration
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.modelContext) var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) var favouriteEntities:
        [PersistedFavouriteStop]
    @State var viewModel = TransitMapViewModel()
    @State var mapRegionUpdateTask: Task<Void, Never>?
    @State var searchUpdateContinuation: AsyncStream<String>.Continuation?
    @State var nearbyStopsUpdateTask: Task<Void, Never>?
    @State var shouldCenterOnNextLocation = false
    @State var isMainSheetPresented = false
    @State var isOnboardingPresented = false
    @State var favouriteStopIds: Set<String> = []
    @State var sheetNavigation = TransitSheetNavigationState()
    @State var sheetDetent: BottomSheetDetent = .medium
    @State private var bikeShareStations: [BikeShareStation] = []
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

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
                detent: sheetDetent,
                navigation: sheetNavigation,
                viewModel: sheetPresentationModel,
                actions: sheetActions,
                activateRoute: activateSheetRoute
            )
            .presentationDetents(
                BottomSheetDetent.presentationDetents,
                selection: sheetPresentationDetent
            )
			.presentationBackground(Color(uiColor: .systemBackground))
            .presentationBackgroundInteraction(
                .enabled(upThrough: BottomSheetDetent.mediumPresentationDetent)
            )
            .presentationCornerRadius(40)
            .interactiveDismissDisabled()
        }
        .fullScreenCover(
            isPresented: onboardingPresentationBinding,
            onDismiss: {
                if hasCompletedOnboarding {
                    isMainSheetPresented = true
                }
            }
        ) {
            OnboardingView {
                hasCompletedOnboarding = true
                isOnboardingPresented = false
                gtfsUpdateController.checkAutomatically()
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !isMainSheetPresented, !isOnboardingPresented else { return }
            if hasCompletedOnboarding {
                isMainSheetPresented = true
            } else {
                isOnboardingPresented = true
            }
        }
        .onChange(of: isMainSheetPresented) {
            if !isMainSheetPresented, hasCompletedOnboarding, !isOnboardingPresented {
                isMainSheetPresented = true
            }
        }
        .task {
            gtfsUpdateController.loadSnapshot()
            gtfsUpdateController.checkAutomatically()
            viewModel.loadRoutePlanner()
            locationService.startUpdatingIfAllowed()
            await bikeShareService.refreshStaticStations()
            await bikeShareService.refreshAvailability()
            bikeShareStations = await bikeShareService.snapshot()?.stations ?? []
            await viewModel.loadGTFSMapStops(
                using: gtfsService, location: locationService.currentLocation
            )
            await viewModel.loadNearbyStops(
                using: atpClient, location: locationService.currentLocation
            )
            await viewModel.loadNearbyStopRoutes(using: gtfsService)
            await loadAlertsAndCheckDisruptions()
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
            guard viewModel.selectedStop != nil, isShowingStopDetail else {
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
        .task(id: favouriteRefreshTaskKey) {
            guard sheetNavigation.selectedTab == .favourites else { return }
            await refreshFavouriteStops()
            while !Task.isCancelled, sheetNavigation.selectedTab == .favourites {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, sheetNavigation.selectedTab == .favourites else { return }
                await refreshFavouriteStops()
            }
        }
        .onChange(of: viewModel.searchQuery) {
            scheduleSearchUpdate()
        }
        .onChange(of: favouriteEntities) {
            favouriteStopIds = Set(favouriteEntities.map(\.stopId))
            let activeIDs = favouriteStopIds
            viewModel.favouriteDepartureBoards = viewModel.favouriteDepartureBoards.filter {
                activeIDs.contains($0.key)
            }
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

    var map: some View {
        TransitMapView(
            state: MapViewState(
                region: viewModel.cameraRegion,
                cameraUpdateToken: viewModel.cameraUpdateToken,
                liveStops: mapLiveStops,
                gtfsStops: mapGTFSStops,
                selectedStopId: viewModel.selectedStop?.id,
                favouriteStopIds: favouriteStopIds,
                alertStopIds: Set(viewModel.alerts.flatMap(\.affectedStopIds)),
                bikeShareStations: mapBikeShareStations,
                routeOverlay: mapRouteOverlay,
                hideMapPins: shouldHideMapPins
            ),
            selectStop: selectStop,
            selectStopGroup: selectStopGroup,
            regionDidChange: scheduleMapRegionUpdate
        )
        .ignoresSafeArea()
        .accessibilityLabel("Luxembourg transit map")
    }

    var selectedBikeShareStations: [BikeShareStation] {
        guard let option = viewModel.selectedRouteOption else { return [] }
        var seen = Set<String>()
        return option.plan.legs.compactMap { $0.bikeShareDetails }
            .flatMap { [$0.pickupStation, $0.returnStation] }
            .filter { seen.insert($0.id).inserted }
    }

    var mapBikeShareStations: [BikeShareStation] {
        guard preferences.showBikeShareStations, !shouldHideMapPins else { return [] }

        var stations = bikeShareStations
        var indexByID = Dictionary(uniqueKeysWithValues: stations.enumerated().map { ($1.id, $0) })

        for station in selectedBikeShareStations {
            if let index = indexByID[station.id] {
                stations[index] = station
            } else {
                indexByID[station.id] = stations.endIndex
                stations.append(station)
            }
        }

        return stations
    }

    var mapLiveStops: [Stop] {
        guard !shouldHideMapPins else { return [] }
        return viewModel.nearbyStops
            .filter(shouldShowMapStop)
            .deduplicatedByExactName()
    }

    var mapGTFSStops: [Stop] {
        guard !shouldHideMapPins else { return [] }
        let liveStopNames = Set(mapLiveStops.map(\.name))
        return viewModel.gtfsOnlyMapStops
            .filter(shouldShowMapStop)
            .filter { !liveStopNames.contains($0.name) }
            .deduplicatedByExactName()
    }

    private func shouldShowMapStop(_ stop: Stop) -> Bool {
        let hasConfigurableMode = stop.modes.contains {
            $0 == .bus || $0 == .tram || $0 == .train
        }
        guard hasConfigurableMode else { return true }

        return (stop.modes.contains(.bus) && preferences.showBusStops)
            || (stop.modes.contains(.tram) && preferences.showTramStops)
            || (stop.modes.contains(.train) && preferences.showTrainStations)
    }

    var favouriteStops: [Stop] {
        favouriteEntities.map(\.stop)
    }

    var favouriteRefreshKey: String {
        favouriteEntities.map(\.stopId).joined(separator: "|")
    }

    var favouriteRefreshTaskKey: String {
        "\(favouriteRefreshKey)|\(sheetNavigation.selectedTab == .favourites)|\(canLoadLiveFavouriteDepartures)"
    }

    var canLoadLiveFavouriteDepartures: Bool {
        !AppPreferences.shared.offlineMode
            && (appConfiguration.hasATPAccessId || debugTransitDataMode != .normal)
    }

    var departureRefreshKey: String {
        "\(viewModel.selectedStop?.id ?? "none")|\(isShowingStopDetail)"
    }

    var isShowingStopDetail: Bool {
        if case .stopDetail = sheetNavigation.activePath.last { return true }
        return false
    }

    var isShowingRouteDetail: Bool {
        if case .routeTimeline = sheetNavigation.activePath.last { return true }
        return false
    }

    var shouldHideMapPins: Bool {
        isShowingRouteDetail || mapRouteOverlay != nil
    }

    var mapRouteOverlay: RouteMapOverlay? {
        switch sheetNavigation.activePath.last {
        case .routeTimeline:
            return viewModel.routeMapOverlay
        case .lineDetail:
            return viewModel.selectedLineDetail?.mapOverlay
        default:
            return nil
        }
    }

    var onboardingPresentationBinding: Binding<Bool> {
        Binding(
            get: { isOnboardingPresented },
            set: { presented in
                isOnboardingPresented = presented
                if !presented {
                    // Preserve the previous swipe-to-dismiss behaviour while
                    // waiting for the cover's dismissal callback before
                    // presenting the main sheet.
                    hasCompletedOnboarding = true
                }
            }
        )
    }
}

#Preview {
    TransitMapScreen(locationService: LocationService())
        .environment(AppPreferences())
}
