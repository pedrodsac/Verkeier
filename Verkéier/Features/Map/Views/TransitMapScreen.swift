import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

struct TransitMapScreen: View {
    @AppStorage("debugTransitDataMode") var debugTransitDataModeRawValue =
        DebugTransitDataMode.normal.rawValue
    @Environment(\.routeService) var routeService
    @Environment(\.walkingRouter) var walkingRouter
    @Environment(\.gtfsService) var gtfsService
    @Environment(\.liveTransitService) var liveTransitService
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
            TransitMapLayer(
                viewModel: viewModel,
                navigation: sheetNavigation,
                favouriteStopIds: favouriteStopIds,
                bikeShareStations: bikeShareStations,
                selectStop: selectStop,
                selectStopGroup: selectStopGroup,
                regionDidChange: scheduleMapRegionUpdate
            )

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
            // Keep the observation-based preference dependency explicit at
            // this presentation boundary. Sheets have a separate hosting
            // hierarchy, so relying on an inherited object can crash before
            // the sheet's first body is rendered.
            .environment(preferences)
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
            viewModel.loadRoutePlanner()
            locationService.startUpdatingIfAllowed()
            viewModel.gtfsFeedStatus = await gtfsService.refreshIfNeeded(force: false)
            (routeService as? MobiliteitRouteService)?.prepareForRouting()
            await bikeShareService.refreshStaticStations()
            await bikeShareService.refreshAvailability()
            bikeShareStations = await bikeShareService.snapshot()?.stations ?? []
            await viewModel.loadGTFSMapStops(location: locationService.currentLocation, using: gtfsService)
            await viewModel.loadNearbyStops(
                location: locationService.currentLocation,
                using: liveTransitService,
                gtfsService: gtfsService,
                walkingRouter: walkingRouter
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
                await viewModel.loadGTFSMapStops(location: locationService.currentLocation, using: gtfsService)
            }
            scheduleNearbyStopsRefresh()
            calculateWaitingRouteIfNeeded()
        }
        .task(id: departureRefreshKey) {
            guard viewModel.selectedStop != nil, isShowingStopDetail else {
                return
            }
            await viewModel.loadDepartures(using: liveTransitService, gtfsService: gtfsService)
            await viewModel.updateSelectedStopRoutes(using: gtfsService)
            await updateTrackedDepartureIfNeeded()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                await viewModel.loadDepartures(using: liveTransitService, gtfsService: gtfsService)
                await viewModel.updateSelectedStopRoutes(using: gtfsService)
                await updateTrackedDepartureIfNeeded()
            }
        }
        .task(id: favouriteRefreshTaskKey) {
            guard sheetNavigation.selectedTab == .home else { return }
            await refreshFavouriteStops()
            while !Task.isCancelled, sheetNavigation.selectedTab == .home {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, sheetNavigation.selectedTab == .home else { return }
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
    }

    var favouriteStops: [Stop] {
        favouriteEntities.map(\.stop)
    }

    var favouriteRefreshKey: String {
        favouriteEntities.map(\.stopId).joined(separator: "|")
    }

    var favouriteRefreshTaskKey: String {
        "\(favouriteRefreshKey)|\(sheetNavigation.selectedTab == .home)|\(canLoadLiveFavouriteDepartures)"
    }

    var canLoadLiveFavouriteDepartures: Bool {
        // Favourites can always refresh a GTFS-only board; the live relay is
        // additive rather than a prerequisite for a useful widget snapshot.
        liveTransitService.isConfigured || viewModel.gtfsFeedStatus.isReady
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
