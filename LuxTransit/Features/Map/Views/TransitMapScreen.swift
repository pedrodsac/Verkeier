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
    @Environment(\.modelContext) var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) var favouriteEntities:
        [PersistedFavouriteStop]
    @State var viewModel = TransitMapViewModel()
    @State var mapRegionUpdateTask: Task<Void, Never>?
    @State var searchUpdateContinuation: AsyncStream<String>.Continuation?
    @State var nearbyStopsUpdateTask: Task<Void, Never>?
    @State var shouldCenterOnNextLocation = false
    @State var isMainSheetPresented = true
    @State var favouriteStopIds: Set<String> = []
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

    var map: some View {
        TransitMapView(
            state: MapViewState(
                region: viewModel.cameraRegion,
                cameraUpdateToken: viewModel.cameraUpdateToken,
                liveStops: stopsForMode(viewModel.nearbyStops),
                gtfsStops: stopsForMode(viewModel.gtfsOnlyMapStops),
                selectedStopId: viewModel.selectedStop?.id,
                favouriteStopIds: favouriteStopIds,
                alertStopIds: Set(viewModel.alerts.flatMap(\.affectedStopIds)),
                bikeShareStations: mapBikeShareStations,
                routeOverlay: viewModel.activeMapOverlay
            ),
            selectStop: selectStop,
            selectStopGroup: selectStopGroup,
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

    func stopsForMode(_ stops: [Stop]) -> [Stop] {
        guard let mode = viewModel.mapModeFilter else { return stops }
        return stops.filter { $0.modes.contains(mode) }
    }

    var selectedBikeShareStations: [BikeShareStation] {
        guard let option = viewModel.selectedRouteOption else { return [] }
        var seen = Set<String>()
        return option.plan.legs.compactMap { $0.bikeShareDetails }
            .flatMap { [$0.pickupStation, $0.returnStation] }
            .filter { seen.insert($0.id).inserted }
    }

    var mapBikeShareStations: [BikeShareStation] {
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

    var favouriteStops: [Stop] {
        favouriteEntities.map(\.stop)
    }

    var favouriteRefreshKey: String {
        favouriteEntities.map(\.stopId).joined(separator: "|")
    }

    var departureRefreshKey: String {
        "\(viewModel.selectedStop?.id ?? "none")|\(viewModel.sheetContext)"
    }
}

#Preview {
    TransitMapScreen(locationService: LocationService())
}
