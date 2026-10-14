import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

struct TransitMapScreen: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.tripDetailService) var tripDetailService
    @Environment(\.routeService) var routeService
    @Environment(\.walkingRouter) var walkingRouter
    @Environment(\.gtfsService) var gtfsService
    @Environment(\.liveTransitService) var liveTransitService
    @Environment(\.bikeShareService) private var bikeShareService
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.launchOnboardingDidFinish) var launchOnboardingDidFinish
    @Environment(\.avlClient) var avlClient
    @Environment(\.liveActivityManager) var liveActivityManager
    @Environment(\.departureReminderService) var departureReminderService
    @Environment(\.disruptionAlertService) var disruptionAlertService
    @Environment(\.appConfiguration) var appConfiguration
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(MapModel.self) var map
    @Environment(StopDetailModel.self) var stopDetail
    @Environment(LineDetailModel.self) var lineDetail
    @Environment(RoutePlannerModel.self) var routePlanner
    @Environment(SearchModel.self) var search
    @Environment(FavouritesModel.self) var favourites
    @Environment(AlertsModel.self) var alerts
    @Environment(SheetRouter.self) var router
    @Query(sort: \PersistedFavouriteStop.createdAt) var favouriteEntities: [PersistedFavouriteStop]
    @State var tripDetailViewModel = TripDetailViewModel()
    @State var tripDetailReturnRegion: MKCoordinateRegion?
    @State var tripDetailReturnDetent: BottomSheetDetent?
    @State var tripDetailCameraDidFit = false
    @State var mapRegionUpdateTask: Task<Void, Never>?
    @State var searchUpdateContinuation: AsyncStream<String>.Continuation?
    @State var nearbyStopsUpdateTask: Task<Void, Never>?
    @State var isMainSheetPresented = false
    @State var isOnboardingPresented = false
    @State var favouriteStopIds: Set<String> = []
    @State private var bikeShareStations: [BikeShareStation] = []
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    let locationService: LocationService

    var body: some View {
        ZStack(alignment: .bottom) {
            TransitMapLayer(
                tripDetail: tripDetailViewModel,
                favouriteStopIds: favouriteStopIds,
                bikeShareStations: bikeShareStations,
                selectStop: { router.show([.stopDetail($0)]) },
                selectStopGroup: { router.openStopGroup($0, bikeShareStations: $1) },
                regionDidChange: scheduleMapRegionUpdate
            )

            VStack {
                HStack {
                    Spacer()
                    LocationPermissionButton(
                        authorizationStatus: locationService.authorizationStatus,
                        requestLocation: router.requestLocation
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $isMainSheetPresented) {
            TransitBottomSheet(
                viewModel: sheetPresentationModel,
                actions: sheetActions
            )
            .safePresentationPlacement()
            .presentationDetents(
                sizeClass == .compact ? BottomSheetDetent.presentationDetents : [Self.regularWidthPresentationDetent],
                selection: sheetPresentationDetent
            )
            .presentationBackground(Color(uiColor: .systemBackground))
            .presentationBackgroundInteraction(
                sizeClass == .compact ? .enabled(upThrough: BottomSheetDetent.mediumPresentationDetent) : .enabled
            )
            .presentationCornerRadius(40)
            .interactiveDismissDisabled()
            // Keep the observation-based preference dependency explicit at
            // this presentation boundary. Sheets have a separate hosting
            // hierarchy, so relying on an inherited object can crash before
            // the sheet's first body is rendered.
            .environment(preferences)
            .featureModels(router.models)
            .environment(router)
            .scaledToFill()
            .frame(maxWidth: 450)
            .presentationSizing(.fitted)
        }
        .fullScreenCover(
            isPresented: onboardingPresentationBinding,
            onDismiss: {
                if hasCompletedOnboarding {
                    isMainSheetPresented = true
                    launchOnboardingDidFinish()
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
        .onChange(of: preferences.includedRouteModes, initial: true) {
            guard routePlanner.routeFilters.includedModes != preferences.includedRouteModes else { return }
            var filters = routePlanner.routeFilters
            filters.includedModes = preferences.includedRouteModes
            router.updateRouteFilters(filters)
        }
        .onChange(of: isMainSheetPresented) {
            if !isMainSheetPresented, hasCompletedOnboarding, !isOnboardingPresented {
                isMainSheetPresented = true
            }
        }
        .task {
            routePlanner.loadRoutePlanner()
            search.loadRecentStops()
            locationService.startUpdatingIfAllowed()
            favourites.gtfsFeedStatus = await gtfsService.refreshIfNeeded(force: false)
            (routeService as? MobiliteitRouteService)?.prepareForRouting()
            await bikeShareService.refreshStaticStations()
            await bikeShareService.refreshAvailability()
            bikeShareStations = await bikeShareService.snapshot()?.stations ?? []
            await map.loadGTFSMapStops(using: gtfsService)
            await map.loadNearbyStops(
                location: locationService.currentLocation,
                using: liveTransitService,
                gtfsService: gtfsService,
                walkingRouter: walkingRouter
            )
            await map.loadNearbyStopRoutes(using: gtfsService)
            await alerts.refresh(using: avlClient, disruptionAlertService: disruptionAlertService)
        }
        .task {
            await observeSearchUpdates()
        }
        .onChange(of: tripDetailSelection) { _, selection in
            tripDetailNavigationChanged(to: selection)
        }
        .onChange(of: tripDetailViewModel.snapshot?.instance) {
            fitTripDetailMapIfNeeded()
        }
        .task(id: activeTripDetailSelection) {
            guard let selection = activeTripDetailSelection else {
                tripDetailViewModel.deactivate()
                return
            }
            await tripDetailViewModel.observe(selection, using: tripDetailService)
        }
        .sensoryFeedback(.selection, trigger: stopDetail.selectedStop?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: favouriteStopIds.count)
        .onChange(of: locationService.currentLocation) {
            if map.centersOnNextLocation, locationService.currentLocation != nil {
                map.centerOnUserLocation(locationService.currentLocation)
                map.centersOnNextLocation = false
            }
            Task {
                await map.loadGTFSMapStops(using: gtfsService)
            }
            scheduleNearbyStopsRefresh()
            router.calculateWaitingRouteIfNeeded()
        }
        .task(id: favouriteRefreshTaskKey) {
            guard router.selectedTab == .home else { return }
            await refreshFavouriteStops()
            while !Task.isCancelled, router.selectedTab == .home {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, router.selectedTab == .home else { return }
                await refreshFavouriteStops()
            }
        }
        .onChange(of: search.searchQuery) {
            scheduleSearchUpdate()
        }
        .onChange(of: favouriteEntities) {
            favouriteStopIds = Set(favouriteEntities.map(\.stopId))
            favourites.favouriteStops = favouriteStops
            favourites.retainBoards(forStopIDs: favouriteStopIds)
            favourites.mirrorForIntents(in: modelContext)
        }
        .onChange(of: scenePhase, initial: true) {
            router.isSceneActive = scenePhase == .active
        }
        .onAppear {
            favouriteStopIds = Set(favouriteEntities.map(\.stopId))
            favourites.favouriteStops = favouriteStops
            favourites.mirrorForIntents(in: modelContext)
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
        "\(favouriteRefreshKey)|\(router.selectedTab == .home)|\(canLoadLiveFavouriteDepartures)"
    }

    var canLoadLiveFavouriteDepartures: Bool {
        // Favourites can always refresh a GTFS-only board; the live relay is
        // additive rather than a prerequisite for a useful widget snapshot.
        liveTransitService.isConfigured || favourites.gtfsFeedStatus.isReady
    }

    var isShowingRouteDetail: Bool {
        if case .routeTimeline = router.activePath.last { return true }
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

extension View {
    func safePresentationPlacement() -> some View {
        if #available(anyAppleOS 27.0, *) {
            return self.presentationPlacement(.leading)
        } else {
            return self
        }
    }
}

#Preview {
    TransitMapScreen(locationService: LocationService())
        .previewEnvironment()
}
