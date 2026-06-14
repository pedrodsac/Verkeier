import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct TransitMapScreen: View {
    @Environment(\.atpClient) private var atpClient
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.gtfsUpdateController) private var gtfsUpdateController
    @Environment(\.routeService) private var routeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.avlClient) private var avlClient
    @Environment(\.liveActivityManager) private var liveActivityManager
    @Environment(\.appConfiguration) private var appConfiguration
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) private var favouriteEntities:
        [PersistedFavouriteStop]
    @State private var viewModel = TransitMapViewModel()
    @State private var mapRegionUpdateTask: Task<Void, Never>?
    @State private var searchUpdateTask: Task<Void, Never>?
    @State private var nearbyStopsUpdateTask: Task<Void, Never>?
    @State private var shouldCenterOnNextLocation = false
    @State private var isMainSheetPresented = true

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

            if let selectedStop = viewModel.selectedStop, viewModel.sheetContext == .stopDetail {
                GeometryReader { geometryProxy in
                    VStack {
                        Spacer()

                        StopDetailFloatingActions(
                            isFavourite: isFavourite(selectedStop),
                            isRefreshDisabled: viewModel.isLoadingDepartures,
                            toggleFavourite: toggleSelectedFavourite,
                            refreshDepartures: refreshDepartures
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, floatingActionsBottomPadding(in: geometryProxy.size.height))
                    }
                }
                .zIndex(10)
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
        .onChange(of: isMainSheetPresented) {
            if !isMainSheetPresented {
                isMainSheetPresented = true
            }
        }
        .task {
            locationService.startUpdatingIfAllowed()
            viewModel.loadGTFSMapStops(
                using: gtfsService, location: locationService.currentLocation)
            await viewModel.loadNearbyStops(
                using: atpClient, location: locationService.currentLocation)
            await viewModel.loadAlerts(using: avlClient)
            await viewModel.loadFavouriteDepartures(using: atpClient, favourites: favouriteStops)
            gtfsUpdateController.loadSnapshot()
            gtfsUpdateController.checkAutomatically()
        }
        .onChange(of: locationService.currentLocation) {
            if shouldCenterOnNextLocation, locationService.currentLocation != nil {
                viewModel.centerOnUserLocation(locationService.currentLocation)
                shouldCenterOnNextLocation = false
            }
            viewModel.loadGTFSMapStops(
                using: gtfsService, location: locationService.currentLocation)
            scheduleNearbyStopsRefresh()
        }
        .task(id: departureRefreshKey) {
            guard viewModel.selectedStop != nil, viewModel.sheetContext == .stopDetail else {
                return
            }
            await viewModel.loadDepartures(using: atpClient)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                await viewModel.loadDepartures(using: atpClient)
            }
        }
        .task(id: favouriteRefreshKey) {
            await viewModel.loadFavouriteDepartures(using: atpClient, favourites: favouriteStops)
        }
        .onChange(of: viewModel.searchQuery) {
            scheduleSearchUpdate()
        }
        .onChange(of: favouriteEntities) {
            mirrorFavouriteEntitiesForIntents()
        }
        .onAppear {
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
        .onReceive(NotificationCenter.default.publisher(for: .gtfsDidUpdate)) { _ in
            viewModel.loadGTFSMapStops(
                using: gtfsService, location: locationService.currentLocation)
            viewModel.updateSelectedStopRoutes(using: gtfsService)
            updateSearch()
        }
    }

    private var map: some View {
        TransitMapView(
            region: viewModel.cameraRegion,
            cameraUpdateToken: viewModel.cameraUpdateToken,
            liveStops: viewModel.nearbyStops,
            gtfsStops: gtfsOnlyMapStops,
            selectedStopId: viewModel.selectedStop?.id,
            favouriteStopIds: Set(favouriteEntities.map(\.stopId)),
            routePolyline: viewModel.mapRoute?.polyline,
            selectStop: selectStop,
            regionDidChange: scheduleMapRegionUpdate
        )
        .ignoresSafeArea()
        .accessibilityLabel("Luxembourg transit map")
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

    private var gtfsOnlyMapStops: [Stop] {
        viewModel.gtfsMapStops.filter { gtfsStop in
            !viewModel.nearbyStops.contains { liveStop in
                stopsRepresentSamePlace(liveStop, gtfsStop)
            }
        }
    }

    private var sheetPresentationModel: TransitSheetPresentationModel {
        let nearby = NearbyStopsPresentationModel(
            stops: viewModel.nearbyStops,
            isLoading: viewModel.isLoadingNearbyStops,
            errorMessage: viewModel.nearbyStopsErrorMessage
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
                activeAlertCount: viewModel.activeAlertCount
            ),
            search: SearchPresentationModel(
                results: viewModel.searchResults,
                nearbySuggestions: viewModel.nearbyStops,
                isLoadingNearbySuggestions: viewModel.isLoadingNearbyStops
            ),
            stopDetail: StopDetailPresentationModel(
                stop: viewModel.selectedStop,
                routes: viewModel.selectedStopRoutes,
                departures: viewModel.departures,
                isLoadingDepartures: viewModel.isLoadingDepartures,
                errorMessage: viewModel.departuresErrorMessage,
                lastUpdated: viewModel.departuresLastUpdated,
                isStale: viewModel.areDeparturesStale,
                isFavourite: viewModel.selectedStop.map(isFavourite) ?? false,
                trackedDepartureId: liveActivityManager.trackedDepartureId,
                liveActivityErrorMessage: liveActivityManager.lastErrorMessage
            ),
            route: RoutePresentationModel(
                selectedStop: viewModel.selectedStop,
                routePlan: viewModel.routePlan,
                isCalculating: viewModel.isCalculatingRoute,
                errorMessage: viewModel.routeErrorMessage
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
                isCheckingGTFSUpdate: gtfsUpdateController.isChecking
            )
        )
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
        mapRegionUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            viewModel.updateVisibleMapRegion(region, using: gtfsService)
        }
    }

    private func scheduleSearchUpdate() {
        searchUpdateTask?.cancel()
        searchUpdateTask = Task { @MainActor in
            if !viewModel.searchQuery.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            viewModel.searchStops(using: gtfsService)
        }
    }

    private func scheduleNearbyStopsRefresh() {
        nearbyStopsUpdateTask?.cancel()
        nearbyStopsUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.loadNearbyStops(
                using: atpClient, location: locationService.currentLocation)
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
            showSettings: showSettings,
            toggleFavourite: toggleSelectedFavourite,
            toggleFavouriteExpansion: toggleFavouriteExpansion,
            refreshDepartures: refreshDepartures,
            refreshAlerts: refreshAlerts,
            calculateRoute: calculateRoute,
            openRouteInAppleMaps: openRouteInAppleMaps,
            trackDeparture: trackDeparture,
            updateSearch: updateSearch,
            checkGTFSUpdate: checkGTFSUpdate
        )
    }

    private func selectStop(_ stop: Stop) {
        animateSheetChange {
            viewModel.selectStop(stop)
        }
        viewModel.updateSelectedStopRoutes(using: gtfsService)
        viewModel.loadGTFSMapStops(using: gtfsService, location: locationService.currentLocation)
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

    private func animateSheetChange(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.28)) {
                changes()
            }
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
                viewModel.loadGTFSMapStops(
                    using: gtfsService, location: locationService.currentLocation)
            }
        case .notDetermined:
            shouldCenterOnNextLocation = true
            viewModel.requestLocation(using: locationService)
        default:
            viewModel.requestLocation(using: locationService)
        }
    }

    private func refreshDepartures() {
        Task {
            await viewModel.loadDepartures(using: atpClient)
        }
    }

    private func floatingActionsBottomPadding(in height: CGFloat) -> CGFloat {
        switch viewModel.sheetDetent {
        case .collapsed:
            return 72
        case .medium:
            return max((height * 0.50) - 24, 0)
        case .expanded:
            return max(height - 96, 0)
        }
    }

    private func updateSearch() {
        searchUpdateTask?.cancel()
        viewModel.searchStops(using: gtfsService)
    }

    private func checkGTFSUpdate() {
        gtfsUpdateController.checkManually()
    }

    private func calculateRoute() {
        Task {
            await viewModel.calculateRoute(
                using: routeService, from: locationService.currentLocation)
        }
    }

    private func openRouteInAppleMaps() {
        viewModel.openSelectedRouteInAppleMaps(
            using: routeService, from: locationService.currentLocation)
    }

    private func refreshAlerts() {
        Task {
            await viewModel.loadAlerts(using: avlClient)
        }
    }

    private func trackDeparture(_ departure: Departure) {
        guard let selectedStop = viewModel.selectedStop else { return }
        Task {
            await liveActivityManager.startTracking(departure: departure, stop: selectedStop)
        }
    }

    private func isFavourite(_ stop: Stop) -> Bool {
        favouriteEntities.contains { $0.stopId == stop.id }
    }

    private func squaredDistance(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }

    private func stopsRepresentSamePlace(_ lhs: Stop, _ rhs: Stop) -> Bool {
        if lhs.id == rhs.id { return true }

        let namesMatch = lhs.name.normalizedForSearch == rhs.name.normalizedForSearch
        guard namesMatch else { return false }

        return squaredDistance(from: lhs.location, to: rhs.location) < 0.000002
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
        FavouriteStopEntityStore.save(stops: favouriteStops)
    }

    private func handlePendingIntentHandoff() {
        guard let handoff = TransitIntentHandoff.consumePending() else { return }
        handle(handoff)
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
        case .openFavouriteStop(let stopId), .trackNextDeparture(let stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                viewModel.selectStop(favourite)
                viewModel.updateSelectedStopRoutes(using: gtfsService)
                viewModel.sheetDetent = .expanded
            } else {
                viewModel.showSearch()
            }
        case .planRoute(let destinationName):
            viewModel.searchQuery = destinationName
            viewModel.searchStops(using: gtfsService)
            viewModel.showSearch()
        }
    }
}

private struct StopDetailFloatingActions: View {
    let isFavourite: Bool
    let isRefreshDisabled: Bool
    let toggleFavourite: () -> Void
    let refreshDepartures: () -> Void

    var body: some View {
        HStack {
            Button(action: toggleFavourite) {
                Label(
                    isFavourite ? "Remove favourite" : "Save favourite",
                    systemImage: isFavourite ? "star.fill" : "star"
                )
            }
            .tint(isFavourite ? .yellow : nil)

            Spacer()

            Button(action: refreshDepartures) {
                Label("Refresh departures", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshDisabled)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }
}

private struct TransitMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let cameraUpdateToken: Int
    let liveStops: [Stop]
    let gtfsStops: [Stop]
    let selectedStopId: String?
    let favouriteStopIds: Set<String>
    let routePolyline: MKPolyline?
    let selectStop: (Stop) -> Void
    let regionDidChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selectStop: selectStop, regionDidChange: regionDidChange)
    }

    func makeUIView(context: Context) -> MapContainerView {
        MapContainerView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: MapContainerView, context: Context) {
        context.coordinator.selectStop = selectStop
        context.coordinator.regionDidChange = regionDidChange
        context.coordinator.selectedStopId = selectedStopId
        context.coordinator.favouriteStopIds = favouriteStopIds

        let stopAnnotations =
            liveStops.map {
                StopMapAnnotation(stop: $0, layer: .liveNearby)
            }
            + gtfsStops.map {
                StopMapAnnotation(stop: $0, layer: .gtfs)
            }

        view.update(
            snapshot: MapSnapshot(
                region: region,
                cameraUpdateToken: cameraUpdateToken,
                annotations: stopAnnotations,
                routePolyline: routePolyline
            )
        )
    }

    struct MapSnapshot {
        let region: MKCoordinateRegion
        let cameraUpdateToken: Int
        let annotations: [StopMapAnnotation]
        let routePolyline: MKPolyline?
    }

    final class MapContainerView: UIView {
        private let coordinator: Coordinator
        private var mapView: MKMapView?
        private var snapshot: MapSnapshot?
        private var appliedCameraUpdateToken: Int?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(snapshot: MapSnapshot) {
            self.snapshot = snapshot
            setNeedsLayout()
            applySnapshotIfPossible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }

            if mapView == nil {
                let mapView = MKMapView(frame: bounds)
                let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
                configuration.pointOfInterestFilter = MKPointOfInterestFilter(
                    excluding: [.publicTransport])
                mapView.preferredConfiguration = configuration
                mapView.delegate = coordinator
                mapView.showsUserLocation = true
                mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(mapView)
                self.mapView = mapView
            }

            mapView?.frame = bounds
            applySnapshotIfPossible()
        }

        private func applySnapshotIfPossible() {
            guard let mapView, let snapshot, bounds.width > 0, bounds.height > 0 else { return }

            if appliedCameraUpdateToken != snapshot.cameraUpdateToken {
                coordinator.isApplyingRegion = true
                mapView.setRegion(snapshot.region, animated: appliedCameraUpdateToken != nil)
                appliedCameraUpdateToken = snapshot.cameraUpdateToken
            }

            coordinator.syncAnnotations(snapshot.annotations, in: mapView)
            coordinator.syncRoute(snapshot.routePolyline, in: mapView)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var selectStop: (Stop) -> Void
        var regionDidChange: (MKCoordinateRegion) -> Void
        var selectedStopId: String?
        var favouriteStopIds: Set<String> = []
        var isApplyingRegion = false
        private var annotationsByKey: [String: StopMapAnnotation] = [:]
        private var routeOverlay: MKPolyline?

        init(
            selectStop: @escaping (Stop) -> Void,
            regionDidChange: @escaping (MKCoordinateRegion) -> Void
        ) {
            self.selectStop = selectStop
            self.regionDidChange = regionDidChange
        }

        func syncAnnotations(_ annotations: [StopMapAnnotation], in mapView: MKMapView) {
            let nextKeys = Set(annotations.map(\.key))
            let staleKeys = Set(annotationsByKey.keys).subtracting(nextKeys)
            let staleAnnotations = staleKeys.compactMap { annotationsByKey.removeValue(forKey: $0) }
            mapView.removeAnnotations(staleAnnotations)

            for annotation in annotations {
                if let existing = annotationsByKey[annotation.key] {
                    existing.update(stop: annotation.stop)
                    continue
                }

                annotationsByKey[annotation.key] = annotation
                mapView.addAnnotation(annotation)
            }

            for annotation in annotationsByKey.values {
                if let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                    configure(view, for: annotation)
                }
            }
        }

        func syncRoute(_ polyline: MKPolyline?, in mapView: MKMapView) {
            if routeOverlay === polyline {
                return
            }

            if let routeOverlay {
                mapView.removeOverlay(routeOverlay)
                self.routeOverlay = nil
            }

            if let polyline {
                mapView.addOverlay(polyline)
                routeOverlay = polyline
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isApplyingRegion {
                isApplyingRegion = false
                return
            }

            regionDidChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? StopMapAnnotation else { return }
            selectStop(annotation.stop)
            mapView.deselectAnnotation(annotation, animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? StopMapAnnotation else { return nil }

            let identifier = "StopMapAnnotation"
            let view =
                mapView.dequeueReusableAnnotationView(
                    withIdentifier: identifier
                ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )
            view.annotation = annotation
            configure(view, for: annotation)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        private func configure(_ view: MKMarkerAnnotationView, for annotation: StopMapAnnotation) {
            let isSelected = selectedStopId == annotation.stop.id
            let isFavourite = favouriteStopIds.contains(annotation.stop.id)

            view.markerTintColor = markerColor(
                for: annotation.stop,
                isSelected: isSelected,
                isFavourite: isFavourite
            )
            view.glyphTintColor = .white
            view.glyphImage = UIImage(systemName: glyphName(for: annotation.stop))
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.displayPriority = isSelected ? .required : .defaultHigh
            view.canShowCallout = false
        }

        private func markerColor(
            for stop: Stop,
            isSelected: Bool,
            isFavourite: Bool
        ) -> UIColor {
            if stop.modes.contains(.train) { return .systemRed }
            if stop.modes.contains(.tram) { return .systemOrange }
            return .systemBlue
        }

        private func glyphName(for stop: Stop) -> String {
            if stop.modes.contains(.train) { return "train.side.front.car" }
            if stop.modes.contains(.tram) { return "tram.fill" }
            return "bus.fill"
        }
    }
}

private final class StopMapAnnotation: NSObject, MKAnnotation {
    enum Layer {
        case liveNearby
        case gtfs
    }

    private(set) var stop: Stop
    let layer: Layer

    var key: String { "\(layer)-\(stop.id)" }
    var coordinate: CLLocationCoordinate2D { stop.location.coordinate }
    var title: String? { stop.name }

    init(stop: Stop, layer: Layer) {
        self.stop = stop
        self.layer = layer
    }

    func update(stop: Stop) {
        self.stop = stop
    }
}

private struct StopMapMarker: View {
    enum Layer {
        case liveNearby
        case gtfs
    }

    let stop: Stop
    var layer: Layer = .liveNearby
    let isSelected: Bool
    let isFavourite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: markerSize, height: markerSize)
                    .background(markerColor.gradient, in: Circle())
                    .overlay {
                        if layer == .gtfs && !isSelected {
                            Circle().stroke(.white.opacity(0.85), lineWidth: 2)
                        }
                        if isFavourite {
                            Circle().stroke(.yellow, lineWidth: 3)
                        }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop \(stop.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var markerColor: Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return .blue
    }

    private var markerSize: CGFloat {
        if isSelected { return 34 }
        switch layer {
        case .liveNearby: return 30
        case .gtfs: return 24
        }
    }

    private var iconName: String {
        if stop.modes.contains(.train) { return "train.side.front.car" }
        if stop.modes.contains(.tram) { return "tram.fill" }
        return "bus.fill"
    }
}

private struct LocationPermissionButton: View {
    let authorizationStatus: CLAuthorizationStatus
    let requestLocation: () -> Void

    var body: some View {
        Button(action: requestLocation) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "location.fill"
        case .denied, .restricted:
            "location.slash.fill"
        case .notDetermined:
            "location"
        @unknown default:
            "location"
        }
    }

    private var accessibilityLabel: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Center on current location"
        case .denied, .restricted:
            "Location access unavailable"
        case .notDetermined:
            "Allow current location"
        @unknown default:
            "Current location"
        }
    }
}

#Preview {
    TransitMapScreen(locationService: LocationService())
}
