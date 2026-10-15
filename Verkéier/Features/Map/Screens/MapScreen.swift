import CoreSpotlight
import SwiftData
import SwiftUI

/// The full-screen map with the main sheet on top. It starts the app's data
/// loading and passes location updates and incoming links to the models.
struct MapScreen: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(MapModel.self) private var map
    @Environment(StopDetailModel.self) private var stopDetail
    @Environment(TripDetailModel.self) private var tripDetail
    @Environment(RoutePlannerModel.self) private var routePlanner
    @Environment(SearchModel.self) private var search
    @Environment(FavouritesModel.self) private var favourites
    @Environment(AlertsModel.self) private var alerts
    @Environment(SheetRouter.self) private var router
    @Environment(LocationService.self) private var locationService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.launchOnboardingDidFinish) private var launchOnboardingDidFinish
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.liveTransitService) private var liveTransitService
    @Environment(\.routeService) private var routeService
    @Environment(\.tripDetailService) private var tripDetailService
    @Environment(\.walkingRouter) private var walkingRouter
    @Environment(\.bikeShareService) private var bikeShareService
    @Environment(\.avlClient) private var avlClient
    @Environment(\.disruptionAlertService) private var disruptionAlertService
    @Environment(\.liveActivityManager) private var liveActivityManager
    @Query(sort: \PersistedFavouriteStop.createdAt) private var savedFavourites: [PersistedFavouriteStop]

    @State private var isMainSheetPresented = false
    @State private var isOnboardingPresented = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack(alignment: .bottom) {
            StopsMap()
            locationButton
        }
        .sensoryFeedback(.selection, trigger: stopDetail.selectedStop?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: favourites.favouriteStops.count)
        .sheet(isPresented: $isMainSheetPresented) { mainSheet }
        .fullScreenCover(isPresented: onboardingPresentationBinding, onDismiss: onboardingDidDismiss) {
            onboarding
        }
        .task { await loadAppData() }
        .task(id: router.liveTripDetailSelection) { await followTripDetail() }
        .task(id: favouriteBoardsRefreshID) { await keepFavouriteBoardsCurrent() }
        .onAppear(perform: appear)
        .onChange(of: isMainSheetPresented) { keepMainSheetPresented() }
        .onChange(of: savedFavourites) { syncSavedFavourites() }
        .onChange(of: locationService.currentLocation) { locationDidChange() }
        .onChange(of: router.tripDetailSelection) { _, selection in router.tripDetailSelectionDidChange(to: selection) }
        .onChange(of: tripDetail.snapshot?.instance) { router.fitMapToTripIfNeeded() }
        .onChange(of: preferences.includedRouteModes, initial: true) {
            router.includeRouteModes(preferences.includedRouteModes)
        }
        .onChange(of: scenePhase, initial: true) { router.isSceneActive = scenePhase == .active }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            openPendingHandoff()
        }
        .onOpenURL { open(TransitIntentHandoff(url: $0)) }
        .onContinueUserActivity(CSSearchableItemActionType) { open(TransitIntentHandoff(spotlightActivity: $0)) }
    }
}

// MARK: - Subviews

private extension MapScreen {
    static let regularWidthPresentationDetent = PresentationDetent.fraction(1)

    var locationButton: some View {
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

    var mainSheet: some View {
        MainSheet()
            .safePresentationPlacement()
            .presentationDetents(
                sizeClass == .compact
                    ? SheetDetent.presentationDetents : [Self.regularWidthPresentationDetent],
                selection: sheetPresentationDetent
            )
            .presentationBackground(Color(uiColor: .systemBackground))
            .presentationBackgroundInteraction(
                sizeClass == .compact ? .enabled(upThrough: SheetDetent.mediumPresentationDetent) : .enabled
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
            .environment(router.locationService)
            .scaledToFill()
            .frame(maxWidth: 450)
            .presentationSizing(.fitted)
    }

    var onboarding: some View {
        OnboardingView {
            hasCompletedOnboarding = true
            isOnboardingPresented = false
        }
        .ignoresSafeArea()
    }

    var sheetPresentationDetent: Binding<PresentationDetent> {
        Binding(
            get: {
                // Regular width (iPad) only supports a single detent, so the
                // selection must match it or UIKit throws.
                sizeClass == .compact ? router.detent.presentationDetent : Self.regularWidthPresentationDetent
            },
            set: { presentationDetent in
                guard sizeClass == .compact else { return }
                router.detent = SheetDetent(presentationDetent: presentationDetent)
            }
        )
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

// MARK: - Lifecycle

private extension MapScreen {
    /// Restarts the favourite board refresh when the favourites change, Home is
    /// shown or hidden, or boards become loadable.
    var favouriteBoardsRefreshID: String {
        let canLoadBoards = liveTransitService.isConfigured || favourites.gtfsFeedStatus.isReady
        let stopIDs = favourites.favouriteStops.map(\.id).joined(separator: "|")
        return "\(stopIDs)|\(router.selectedTab == .home)|\(canLoadBoards)"
    }

    func appear() {
        if !isMainSheetPresented, !isOnboardingPresented {
            if hasCompletedOnboarding {
                isMainSheetPresented = true
            } else {
                isOnboardingPresented = true
            }
        }
        syncSavedFavourites()
        openPendingHandoff()
    }

    /// Loads what the map and Home show once the map is on screen.
    func loadAppData() async {
        routePlanner.loadRoutePlanner()
        search.loadRecentStops()
        locationService.startUpdatingIfAllowed()
        await favourites.refreshFeedStatus(using: gtfsService)
        (routeService as? MobiliteitRouteService)?.prepareForRouting()
        await map.loadBikeShareStations(using: bikeShareService)
        await map.loadStops(
            near: locationService.currentLocation,
            using: liveTransitService,
            gtfsService: gtfsService,
            walkingRouter: walkingRouter
        )
        await alerts.refresh(using: avlClient, disruptionAlertService: disruptionAlertService)
    }

    func followTripDetail() async {
        guard let selection = router.liveTripDetailSelection else {
            tripDetail.deactivate()
            return
        }
        await tripDetail.observe(selection, using: tripDetailService)
    }

    func keepFavouriteBoardsCurrent() async {
        guard router.selectedTab == .home else { return }
        await favourites.keepBoardsCurrent(using: liveTransitService, gtfsService: gtfsService)
    }

    func syncSavedFavourites() {
        favourites.savedFavouritesDidChange(savedFavourites.map(\.stop), in: modelContext)
    }

    func locationDidChange() {
        map.locationDidChange(
            to: locationService.currentLocation,
            using: liveTransitService,
            gtfsService: gtfsService,
            walkingRouter: walkingRouter
        )
        router.calculateWaitingRouteIfNeeded()
    }

    func keepMainSheetPresented() {
        if !isMainSheetPresented, hasCompletedOnboarding, !isOnboardingPresented {
            isMainSheetPresented = true
        }
    }

    func onboardingDidDismiss() {
        if hasCompletedOnboarding {
            isMainSheetPresented = true
            launchOnboardingDidFinish()
        }
    }

    func openPendingHandoff() {
        open(TransitIntentHandoff.consumePending())
    }

    func open(_ handoff: TransitIntentHandoff?) {
        guard let handoff else { return }
        router.handle(handoff, liveTransitService: liveTransitService, liveActivityManager: liveActivityManager)
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
    MapScreen()
        .previewEnvironment()
}
