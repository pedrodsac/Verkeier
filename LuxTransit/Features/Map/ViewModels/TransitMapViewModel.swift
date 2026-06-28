import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class TransitMapViewModel {
    var cameraRegion: MKCoordinateRegion
    var cameraUpdateToken = 0
    var sheetContext: TransitSheetContext = .home
    var sheetDetent: BottomSheetDetent = .medium
    var nearbyStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }

    var gtfsMapStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }

    private(set) var gtfsOnlyMapStops: [Stop] = []
    /// When set, only stops served by this mode are shown on the map. `nil` = all.
    var mapModeFilter: TransportMode?
    /// Routes serving each nearby stop, keyed by stop id, for the nearby list.
    var nearbyStopRoutes: [String: [TransitRoute]] = [:]
    var selectedStop: Stop?
    var selectedStopRoutes: [TransitRoute] = [] {
        didSet { rebuildDepartureFilters() }
    }

    var isLoadingNearbyStops = false
    var nearbyStopsErrorMessage: String?
    var departures: [Departure] = [] {
        didSet { rebuildDepartureFilters() }
    }

    var offlineScheduledDepartures: [OfflineScheduleDeparture] = []
    var selectedDepartureLine: String? {
        didSet { rebuildDepartureFilters() }
    }

    var selectedDeparturePlatform: String? {
        didSet { rebuildDepartureFilters() }
    }

    private(set) var availableDeparturePlatforms: [String] = []
    private(set) var filteredDepartures: [Departure] = []
    var isLoadingDepartures = false
    var departuresErrorMessage: String?
    var departuresLastUpdated: Date?
    var favouriteDeparturesByStopId: [String: [Departure]] = [:]
    var isLoadingFavouriteDepartures = false
    var favouriteDeparturesErrorMessage: String?
    var favouriteDeparturesLastUpdated: Date?
    var expandedFavouriteStopIds: Set<String> = []
    var searchQuery = ""
    var searchResults: [Stop] = []
    var routeOrigin: RoutePlace?
    var routeDestination: RoutePlace?
    var routeFilters = AppPreferences.shared.defaultRouteFilters
    var routePlanningTime: RoutePlanningTime = .leaveNow
    var recentRoutePlaces: [RoutePlace] = []
    var recentStops: [Stop] = []
    var recentTrips: [RouteCommutePreset] = []
    var commutePresets: [RouteCommutePreset] = []
    var routeOptions: [RouteOption] = []
    var selectedRouteOptionID: String?
    var visibleRouteOptionCount = 0
    var routeLoadingPhase: RouteLoadingPhase = .idle
    var routeErrorMessage: String?
    var routeStatusMessage: String?
    var alerts: [AlertMessage] = []
    var selectedLineDetailRoute: TransitRoute?
    var selectedLineDetailDirectionID: String?
    var selectedLineDetail: LineDetail?
    var selectedLineDetailErrorMessage: String?
    var isLoadingAlerts = false
    var alertsErrorMessage: String?
    var alertsLastUpdated: Date?

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.6116, longitude: 6.1319),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )
    private let minimumMapSpan = 0.001
    private let favouriteDepartureConcurrencyLimit = 3
    private let nearbyRouteConcurrencyLimit = 10
    private let routeOptionInitialVisibleCount = 5
    private var visibleMapRegion: MKCoordinateRegion?
    private let now: @Sendable () -> Date
    private var routeCalculationGeneration = 0
    private var unfilteredRouteOptions: [RouteOption] = []

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
        cameraRegion = defaultRegion
    }

    var routePlan: RoutePlan? {
        selectedRouteOption?.plan
    }

    var routeMapOverlay: RouteMapOverlay? {
        selectedRouteOption?.mapOverlay
    }

    var activeMapOverlay: RouteMapOverlay? {
        if sheetContext == .lineDetail {
            return selectedLineDetail?.mapOverlay
        }
        return routeMapOverlay
    }

    var isWaitingForRouteLocation: Bool {
        routeLoadingPhase.isWaitingForLocation
    }

    var isCalculatingRoute: Bool {
        routeLoadingPhase.isCalculating
    }

    var selectedRouteOption: RouteOption? {
        guard !routeOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
           let match = routeOptions.first(where: { $0.id == selectedRouteOptionID }) {
            return match
        }
        return routeOptions.first
    }

    var visibleRouteOptions: [RouteOption] {
        Array(routeOptions.prefix(visibleRouteOptionCount))
    }

    func requestLocation(using locationService: LocationService) {
        locationService.requestWhenInUseAuthorization()
    }

    func setMapModeFilter(_ mode: TransportMode?) {
        mapModeFilter = mode
    }

    func showHome() {
        sheetContext = .home
        sheetDetent = .medium
        clearRoute()
        clearLineDetail()
    }

    func showSearch() {
        sheetContext = .search
        sheetDetent = .expanded
        clearRoute()
        clearLineDetail()
    }

    func showAlerts() {
        sheetContext = .alerts
        sheetDetent = .expanded
        clearRoute()
    }

    func showStopDetail() {
        guard selectedStop != nil else {
            showHome()
            return
        }
        sheetContext = .stopDetail
        sheetDetent = .medium
    }

    func showSettings() {
        sheetContext = .settings
        sheetDetent = .expanded
        clearRoute()
        clearLineDetail()
    }

    func showDirections() {
        guard routeDestination != nil || selectedStop != nil else { return }
        sheetContext = .directions
        sheetDetent = .medium
    }

    func showRouteTimeline() {
        guard selectedRouteOption != nil else { return }
        sheetContext = .routeTimeline
        sheetDetent = .expanded
    }

    func showLineDetail(_ route: TransitRoute) {
        selectedLineDetailRoute = route
        selectedLineDetailDirectionID = nil
        sheetContext = .lineDetail
        sheetDetent = .expanded
    }

    func selectLineDetailDirection(_ directionID: String) {
        selectedLineDetailDirectionID = directionID
    }

    func toggleFavouriteExpansion(stopId: String) {
        if expandedFavouriteStopIds.contains(stopId) {
            expandedFavouriteStopIds.remove(stopId)
        } else {
            expandedFavouriteStopIds.insert(stopId)
        }
    }

    func loadNearbyStops(using atpClient: any ATPClient, location: CLLocation?) async {
        isLoadingNearbyStops = true
        nearbyStopsErrorMessage = nil

        let coordinate = location?.coordinate ?? defaultRegion.center

        do {
            nearbyStops = try await atpClient.nearbyStops(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            nearbyStops = []
            nearbyStopsErrorMessage = "Nearby stops could not be loaded."
        }

        isLoadingNearbyStops = false
    }

    /// Loads the lines serving each nearby stop, with bounded concurrency, so
    /// the nearby list can show "12 · 14 · 25" rather than just a mode label.
    func loadNearbyStopRoutes(using gtfsService: any GTFSService) async {
        let stops = nearbyStops
        guard !stops.isEmpty else {
            nearbyStopRoutes = [:]
            return
        }

        var result: [String: [TransitRoute]] = [:]
        await withTaskGroup(of: (String, [TransitRoute]).self) { group in
            var iterator = stops.makeIterator()
            for _ in 0 ..< min(nearbyRouteConcurrencyLimit, stops.count) {
                guard let stop = iterator.next() else { break }
                group.addTask { await (stop.id, gtfsService.routesForStop(id: stop.id)) }
            }

            while let (id, routes) = await group.next() {
                if !routes.isEmpty { result[id] = routes }
                if let stop = iterator.next() {
                    group.addTask { await (stop.id, gtfsService.routesForStop(id: stop.id)) }
                }
            }
        }
        nearbyStopRoutes = result
    }

    func loadGTFSMapStops(using gtfsService: any GTFSService, location _: CLLocation?) async {
        let region = visibleMapRegion ?? cameraRegion
        await loadGTFSMapStops(using: gtfsService, region: region)
    }

    func updateVisibleMapRegion(_ region: MKCoordinateRegion, using gtfsService: any GTFSService) async {
        guard let region = sanitized(region) else { return }
        visibleMapRegion = region
        await loadGTFSMapStops(using: gtfsService, region: region)
    }

    private func loadGTFSMapStops(using gtfsService: any GTFSService, region: MKCoordinateRegion) async {
        guard let region = sanitized(region) else { return }
        let coordinate = region.center
        let center = LocationPoint(
            name: "Visible map center",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        gtfsMapStops = await gtfsService.stopsForMap(
            center: center,
            latitudeDelta: max(region.span.latitudeDelta, defaultRegion.span.latitudeDelta),
            longitudeDelta: max(region.span.longitudeDelta, defaultRegion.span.longitudeDelta),
            limit: 180
        )
    }

    private func sanitized(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
        let latitude = region.center.latitude
        let longitude = region.center.longitude
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta

        guard latitude.isFinite,
              longitude.isFinite,
              latitudeDelta.isFinite,
              longitudeDelta.isFinite,
              (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude),
              latitudeDelta > 0,
              longitudeDelta > 0
        else {
            return nil
        }

        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latitudeDelta, minimumMapSpan), 2.0),
                longitudeDelta: min(max(longitudeDelta, minimumMapSpan), 2.0)
            )
        )
    }

    func loadFavouriteDepartures(using atpClient: any ATPClient, favourites: [Stop]) async {
        let limitedFavourites = Array(favourites.prefix(6))

        guard !limitedFavourites.isEmpty else {
            favouriteDeparturesByStopId = [:]
            favouriteDeparturesErrorMessage = nil
            favouriteDeparturesLastUpdated = nil
            isLoadingFavouriteDepartures = false
            return
        }

        isLoadingFavouriteDepartures = true
        favouriteDeparturesErrorMessage = nil

        let results = await loadFavouriteDepartureBoards(
            using: atpClient,
            favourites: limitedFavourites
        )
        let boards = Dictionary(uniqueKeysWithValues: results.map { ($0.stopId, $0.departures) })
        let failedCount = results.filter(\.didFail).count

        favouriteDeparturesByStopId = boards
        favouriteDeparturesLastUpdated = .now
        favouriteDeparturesErrorMessage =
            failedCount == limitedFavourites.count
                ? "Favourite departures could not be loaded." : nil
        isLoadingFavouriteDepartures = false
    }

    func selectStop(_ stop: Stop, using store: RoutePlannerStore = .shared) {
        selectedStop = stop
        recentStops = store.recordRecentStop(stop)
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
        clearLineDetail()
        selectedStopRoutes = []
        departures = []
        offlineScheduledDepartures = []
        selectedDepartureLine = nil
        selectedDeparturePlatform = nil
        departuresErrorMessage = nil
        departuresLastUpdated = nil
        routeErrorMessage = nil
        clearRoute()
        sheetContext = .stopDetail
        sheetDetent = .medium
        moveCamera(to: anchoredRegion(
            for: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func loadRoutePlanner(using store: RoutePlannerStore = .shared) {
        recentRoutePlaces = store.recentPlaces()
        commutePresets = store.commutePresets()
        recentStops = store.recentStops()
        recentTrips = store.recentTrips()
    }

    /// A commute preset to highlight on the home sheet based on the time of day:
    /// in the morning window (06:00–10:30) the first "Home → Work" preset, in the
    /// evening window (16:00–20:00) the last "Work → Home" preset. `nil` outside
    /// those windows or when no matching preset exists.
    var suggestedCommutePreset: RouteCommutePreset? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now())
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let minutesOfDay = hour * 60 + minute

        if (360 ... 630).contains(minutesOfDay) {
            return commutePresets.first { titleHasOrder($0.title, "Home", "Work") }
        }
        if (960 ... 1200).contains(minutesOfDay) {
            return commutePresets.last { titleHasOrder($0.title, "Work", "Home") }
        }
        return nil
    }

    /// True when `title` contains both keywords and `first` appears before `second`.
    private func titleHasOrder(_ title: String, _ first: String, _ second: String) -> Bool {
        let lower = title.lowercased()
        guard let firstRange = lower.range(of: first.lowercased()),
              let secondRange = lower.range(of: second.lowercased()) else { return false }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    func selectRouteOrigin(_ place: RoutePlace?, using store: RoutePlannerStore = .shared) {
        routeOrigin = place
        if let place {
            recentRoutePlaces = store.recordRecentPlace(place)
        }
        clearRoute()
    }

    func selectRouteDestination(_ place: RoutePlace, using store: RoutePlannerStore = .shared) {
        routeDestination = place
        recentRoutePlaces = store.recordRecentPlace(place)
        clearRoute()
    }

    func applyCommutePreset(_ presetID: String, using store: RoutePlannerStore = .shared) {
        let preset = commutePresets.first(where: { $0.id == presetID })
            ?? recentTrips.first(where: { $0.id == presetID })
        guard let preset else { return }
        routeOrigin = preset.origin
        routeDestination = preset.destination
        recentRoutePlaces = store.recordRecentPlace(preset.destination)
        clearRoute()
    }

    func saveCurrentCommutePreset(title customTitle: String = "", using store: RoutePlannerStore = .shared) {
        guard let destination = effectiveRouteDestination else { return }

        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = if !trimmed.isEmpty {
            trimmed
        } else if let routeOrigin {
            "\(routeOrigin.title) to \(destination.title)"
        } else {
            "Current Location to \(destination.title)"
        }

        let preset = RouteCommutePreset(
            title: title,
            origin: routeOrigin,
            destination: destination
        )
        var updated = commutePresets.filter {
            !($0.origin == preset.origin && $0.destination == preset.destination)
        }
        updated.insert(preset, at: 0)
        if updated.count > 6 {
            updated = Array(updated.prefix(6))
        }
        commutePresets = updated
        store.saveCommutePresets(updated)
    }

    func swapRouteEndpoints() {
        guard let destination = effectiveRouteDestination else { return }
        let previousOrigin = routeOrigin
        routeOrigin = destination
        routeDestination = previousOrigin
        clearRoute()
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        routeFilters = filters
        applyRouteOptions(preferredID: selectedRouteOptionID, announceFallback: true)
    }

    func loadDepartures(using atpClient: any ATPClient) async {
        guard let selectedStop else { return }
        isLoadingDepartures = true
        departuresErrorMessage = nil

        do {
            departures = try await atpClient.departureBoards(stopIds: selectedStop.platformIds)
            departuresLastUpdated = .now
        } catch {
            departures = []
            departuresErrorMessage = "Departures could not be loaded."
        }

        isLoadingDepartures = false
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        if selectedDepartureLine == route.id {
            selectedDepartureLine = nil
        } else {
            selectedDepartureLine = route.id
        }

        clearSelectedPlatformIfUnavailable()
    }

    func selectDeparturePlatform(_ platform: String?) {
        selectedDeparturePlatform = platform
    }

    func searchStops(using gtfsService: any GTFSService) async {
        let query = searchQuery
        async let gtfsLookup = gtfsService.searchStops(query: query)
        async let mapKitLookup = Self.mapKitStops(matching: query)

        let gtfsResults = await Array(gtfsLookup.prefix(80))
        // Drop MapKit hits that land on top of a GTFS stop we already returned.
        let mapKitResults = await mapKitLookup.filter { place in
            !gtfsResults.contains { Self.areWithin(100, place, $0) }
        }

        // A newer keystroke may have superseded this query while MapKit ran.
        guard query == searchQuery else { return }
        searchResults = gtfsResults + mapKitResults
    }

    /// Runs an address/POI search bounded to Luxembourg and maps the hits to
    /// ``Stop`` values tagged ``DataSource/mapKit``.
    private static func mapKitStops(matching query: String) async -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.8153, longitude: 6.1296),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap(mapKitStop)
    }

    private static func mapKitStop(from item: MKMapItem) -> Stop? {
        let coordinate = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        return Stop(
            id: "mapkit:\(coordinate.latitude),\(coordinate.longitude)",
            name: item.name ?? "Place",
            location: LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            modes: [],
            dataSource: .mapKit
        )
    }

    private static func areWithin(_ meters: CLLocationDistance, _ lhs: Stop, _ rhs: Stop) -> Bool {
        CLLocation(latitude: lhs.location.latitude, longitude: lhs.location.longitude)
            .distance(from: CLLocation(latitude: rhs.location.latitude, longitude: rhs.location.longitude)) < meters
    }

    func updateSelectedStopRoutes(using gtfsService: any GTFSService) async {
        guard let selectedStop else {
            selectedStopRoutes = []
            return
        }

        let directRoutes = await gtfsService.routesForStop(id: selectedStop.id)
        if !directRoutes.isEmpty {
            selectedStopRoutes = directRoutes
            return
        }

        let matchedStops = await gtfsService.searchStops(query: selectedStop.name)
        let routeCandidateStops = matchedStops
            .filter { $0.name.normalizedForSearch == selectedStop.name.normalizedForSearch }
            .sorted {
                squaredDistance(from: $0.location, to: selectedStop.location)
                    < squaredDistance(from: $1.location, to: selectedStop.location)
            }
        for stop in routeCandidateStops {
            let routes = await gtfsService.routesForStop(id: stop.id)
            if !routes.isEmpty {
                selectedStopRoutes = routes
                return
            }
        }

        selectedStopRoutes = []
    }

    func loadOfflineScheduledDepartures(
        using gtfsService: any GTFSService,
        now: Date = .now
    ) async {
        guard let selectedStop,
              let timetable = await gtfsService.timetableIndex() else {
            offlineScheduledDepartures = []
            return
        }

        let service = OfflineScheduleService()
        offlineScheduledDepartures = service.upcomingDepartures(
            for: selectedStop,
            timetable: timetable,
            now: now
        )
    }

    func calculateRoute(using routeService: any RouteService, from location: CLLocation?) async {
        guard let destination = effectiveRouteDestination else {
            routeLoadingPhase = .idle
            routeErrorMessage = "Choose a route destination first."
            return
        }

        let origin: LocationPoint
        if let routeOrigin {
            origin = routeOrigin.location
        } else {
            guard let location else {
                clearRouteResult()
                routeLoadingPhase = .waitingForLocation
                routeErrorMessage = nil
                return
            }

            origin = LocationPoint(
                name: "Current Location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }

        if routeOrigin == nil, location == nil {
            clearRouteResult()
            routeLoadingPhase = .waitingForLocation
            routeErrorMessage = nil
            return
        }

        let requestGeneration = startRouteRequest()
        routeLoadingPhase = .calculating
        routeErrorMessage = nil
        routeStatusMessage = nil
        sheetContext = .directions

        do {
            let calculation = try await routeService.calculateRoute(
                from: origin, to: destination.location, time: routePlanningTime, filters: routeFilters
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            unfilteredRouteOptions = calculation.options
            applyRouteOptions(preferredID: calculation.selectedOptionID, announceFallback: false)
            if !calculation.options.isEmpty {
                recentTrips = RoutePlannerStore.shared.recordRecentTrip(
                    origin: routeOrigin, destination: destination
                )
            }
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            clearRouteResult()
            routeErrorMessage = routeErrorMessage(for: error)
        }

        if requestGeneration == routeCalculationGeneration {
            routeLoadingPhase = .idle
        }
    }

    func failRouteLocationRequest() {
        clearRouteResult()
        routeLoadingPhase = .idle
        routeErrorMessage = "Current location is required to calculate a route."
        sheetContext = .directions
    }

    @discardableResult
    func selectRouteOption(id: String) -> Bool {
        guard routeOptions.contains(where: { $0.id == id }) else { return false }
        selectedRouteOptionID = id
        routeStatusMessage = nil
        return true
    }

    func showMoreRouteOptions() {
        guard !routeOptions.isEmpty else { return }

        if visibleRouteOptionCount < routeOptions.count {
            visibleRouteOptionCount = min(routeOptions.count, visibleRouteOptionCount + 3)
            routeStatusMessage = nil
        }
    }

    func openSelectedRouteInAppleMaps(
        using routeService: any RouteService, from location: CLLocation?
    ) {
        guard let destination = effectiveRouteDestination else { return }

        let origin: LocationPoint
        if let routeOrigin {
            origin = routeOrigin.location
        } else {
            guard let location else { return }
            origin = LocationPoint(
                name: "Current Location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }

        routeService.openInAppleMaps(from: origin, to: destination.location)
    }

    func loadAlerts(using avlClient: any AVLClient) async {
        isLoadingAlerts = true
        alertsErrorMessage = nil

        do {
            alerts = try await avlClient.fetchMessages()
            alertsLastUpdated = .now
        } catch {
            alerts = []
            alertsErrorMessage = "AVL alerts could not be loaded."
        }

        isLoadingAlerts = false
    }

    /// After an AVL refresh, notify the rider about any new disruption that
    /// affects a line serving one of their favourite stops. Resolves the favourite
    /// stops' route ids with bounded fan-out, then defers to
    /// ``DisruptionAlertService`` to dedupe and deliver.
    func checkDisruptionAlerts(
        using gtfsService: any GTFSService,
        disruptionAlertService: DisruptionAlertService,
        favouriteStops: [Stop]
    ) async {
        guard !favouriteStops.isEmpty, !alerts.isEmpty else { return }

        let favouriteRouteIds = await Set(
            withTaskGroup(of: [TransitRoute].self) { group in
                for stop in favouriteStops {
                    group.addTask { await gtfsService.routesForStop(id: stop.id) }
                }
                return await group.reduce(into: []) { $0 += $1 }
            }.map(\.id)
        )

        await disruptionAlertService.checkAlerts(alerts, favouriteRouteIds: favouriteRouteIds)
    }

    func loadLineDetail(using gtfsService: any GTFSService, now: Date = .now) async {
        guard let route = selectedLineDetailRoute,
              let timetable = await gtfsService.timetableIndex() else {
            selectedLineDetail = nil
            selectedLineDetailErrorMessage = "Line details are not available yet."
            return
        }

        let service = LineDetailService()
        selectedLineDetail = service.detail(
            for: route,
            selectedStopId: selectedStop?.id,
            timetable: timetable,
            now: now,

            selectedDirectionID: selectedLineDetailDirectionID
        )
        selectedLineDetailErrorMessage =
            selectedLineDetail == nil ? "No GTFS timetable details are available for this line." : nil
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        guard let favouriteDeparturesLastUpdated else { return false }
        return Date().timeIntervalSince(favouriteDeparturesLastUpdated) > 90
    }

    var areAlertsStale: Bool {
        guard let alertsLastUpdated else { return false }
        return Date().timeIntervalSince(alertsLastUpdated) > 300
    }

    var activeAlertCount: Int {
        alerts.count
    }

    var stopDetailAlerts: [AlertMessage] {
        guard let selectedStop else { return [] }
        let routeIDs = Set(selectedStopRoutes.map(\.id))
        return alerts.filter { alert in
            alert.affectedStopIds.contains(selectedStop.id)
                || !routeIDs.isDisjoint(with: alert.affectedRouteIds)
        }
    }

    var routeAlerts: [AlertMessage] {
        guard let selectedRouteOption else { return [] }
        let routeIDs = Set(selectedRouteOption.plan.legs.compactMap(\.routeId))
        let stopIDs = Set(selectedRouteOption.plan.legs.flatMap { leg in
            [leg.originStopId, leg.destinationStopId].compactMap(\.self)
        })
        return alerts.filter { alert in
            !routeIDs.isDisjoint(with: alert.affectedRouteIds)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }

    /// Active alerts that affect each transit leg of the selected route plan,
    /// keyed by leg index (as a string). Walking legs are skipped.
    var routeLegAlerts: [String: [AlertMessage]] {
        guard let plan = selectedRouteOption?.plan else { return [:] }
        var result: [String: [AlertMessage]] = [:]
        for (index, leg) in plan.legs.enumerated() where leg.transportKind == .transit {
            let legStopIDs = Set([leg.originStopId, leg.destinationStopId].compactMap(\.self))
            let matching = alerts.filter { alert in
                if let routeID = leg.routeId, alert.affectedRouteIds.contains(routeID) {
                    return true
                }
                return !legStopIDs.isDisjoint(with: alert.affectedStopIds)
            }
            if !matching.isEmpty { result[String(index)] = matching }
        }
        return result
    }

    var lineDetailAlerts: [AlertMessage] {
        guard let route = selectedLineDetailRoute else { return [] }
        let stopIDs = Set(selectedLineDetail?.stopSequence.map(\.id) ?? [])
        return alerts.filter { alert in
            alert.affectedRouteIds.contains(route.id)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: anchoredRegion(
            for: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }

    private func clearRoute() {
        routeCalculationGeneration += 1
        clearRouteResult()
        routeErrorMessage = nil
        routeLoadingPhase = .idle
    }

    private func clearLineDetail() {
        selectedLineDetailRoute = nil
        selectedLineDetailDirectionID = nil
        selectedLineDetail = nil
        selectedLineDetailErrorMessage = nil
    }

    private func clearRouteResult() {
        unfilteredRouteOptions = []
        routeOptions = []
        selectedRouteOptionID = nil
        visibleRouteOptionCount = 0
        routeStatusMessage = nil
    }

    private var effectiveRouteDestination: RoutePlace? {
        routeDestination ?? selectedStop.map { RoutePlace(stop: $0, source: .selectedStop) }
    }

    private func startRouteRequest() -> Int {
        routeCalculationGeneration += 1
        return routeCalculationGeneration
    }

    private func selectBestRouteOption(preferredID: String?, announceFallback: Bool) {
        guard !routeOptions.isEmpty else {
            selectedRouteOptionID = nil
            return
        }

        let viableStatuses: Set<RouteOptionStatus> = [.viable, .scheduledOnly, .atRisk]
        let optionsByID = Dictionary(uniqueKeysWithValues: routeOptions.map { ($0.id, $0) })

        if let preferredID,
           let preferred = optionsByID[preferredID],
           viableStatuses.contains(preferred.status(at: now())) {
            selectedRouteOptionID = preferredID
            return
        }

        if let replacement = routeOptions.first(where: { viableStatuses.contains($0.status(at: now())) }) {
            let changed = replacement.id != preferredID
            selectedRouteOptionID = replacement.id
            if announceFallback, changed, preferredID != nil {
                routeStatusMessage = "Showing the next available route."
            }
            return
        }

        selectedRouteOptionID = routeOptions.first?.id
    }

    private func applyRouteOptions(preferredID: String?, announceFallback: Bool) {
        let filtered = filteredRouteOptions(from: unfilteredRouteOptions)
        let didRelaxFilters = filtered.isEmpty && !unfilteredRouteOptions.isEmpty
        routeOptions = (didRelaxFilters ? unfilteredRouteOptions : filtered)
            .sorted(by: compareRouteOptions)
        visibleRouteOptionCount = min(routeOptionInitialVisibleCount, routeOptions.count)
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)

        if didRelaxFilters {
            routeStatusMessage = "No routes matched all filters. Showing the closest alternatives."
        } else if routeOptions.isEmpty {
            routeStatusMessage = nil
        }
    }

    private func filteredRouteOptions(from options: [RouteOption]) -> [RouteOption] {
        options.filter { option in
            if routeFilters.avoidTightTransfers, option.status(at: now()) == .atRisk {
                return false
            }

            if routeFilters.preferAccessible {
                let walkingDistance = option.walkingDistanceMeters
                if walkingDistance > 700 || option.transferCount > 1 {
                    return false
                }
            }

            guard let mode = routeFilters.modePreference.transportMode else {
                return true
            }
            return option.transitLegs.contains(where: { $0.mode == mode })
        }
    }

    private func compareRouteOptions(_ lhs: RouteOption, _ rhs: RouteOption) -> Bool {
        let preferredMode = routeFilters.modePreference.transportMode
        let lhsModeRank = preferredMode.map { mode in
            lhs.transitLegs.contains(where: { $0.mode == mode }) ? 0 : 1
        } ?? 0
        let rhsModeRank = preferredMode.map { mode in
            rhs.transitLegs.contains(where: { $0.mode == mode }) ? 0 : 1
        } ?? 0
        if lhsModeRank != rhsModeRank {
            return lhsModeRank < rhsModeRank
        }

        switch routeFilters.sort {
        case .fastest:
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        case .fewestTransfers:
            if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        case .leastWalking:
            let lhsWalking = lhs.walkingDistanceMeters
            let rhsWalking = rhs.walkingDistanceMeters
            if lhsWalking != rhsWalking { return lhsWalking < rhsWalking }
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        }

        return lhs.id < rhs.id
    }

    private func routeErrorMessage(for error: Error) -> String {
        guard let routingError = error as? RoutingError else {
            return "A public transport route could not be calculated."
        }

        switch routingError {
        case .timetableUnavailable:
            return "Public transport schedules are not available yet."
        case .noPublicTransportRoute, .noRouteFound:
            return "No public transport route was found."
        }
    }

    private func loadFavouriteDepartureBoards(
        using atpClient: any ATPClient,
        favourites: [Stop]
    ) async -> [FavouriteDepartureBoardResult] {
        await withTaskGroup(of: FavouriteDepartureBoardResult.self) { group in
            var results: [FavouriteDepartureBoardResult] = []
            results.reserveCapacity(favourites.count)

            var iterator = favourites.enumerated().makeIterator()
            for _ in 0 ..< min(favouriteDepartureConcurrencyLimit, favourites.count) {
                guard let next = iterator.next() else { break }
                group.addTask {
                    await Self.loadFavouriteDepartureBoard(
                        using: atpClient,
                        stop: next.element,
                        index: next.offset
                    )
                }
            }

            while let result = await group.next() {
                results.append(result)
                if let next = iterator.next() {
                    group.addTask {
                        await Self.loadFavouriteDepartureBoard(
                            using: atpClient,
                            stop: next.element,
                            index: next.offset
                        )
                    }
                }
            }

            return results.sorted { $0.index < $1.index }
        }
    }

    private static func loadFavouriteDepartureBoard(
        using atpClient: any ATPClient,
        stop: Stop,
        index: Int
    ) async -> FavouriteDepartureBoardResult {
        do {
            return try await FavouriteDepartureBoardResult(
                stopId: stop.id,
                departures: atpClient.departureBoards(stopIds: stop.platformIds),
                didFail: false,
                index: index
            )
        } catch {
            return FavouriteDepartureBoardResult(
                stopId: stop.id,
                departures: [],
                didFail: true,
                index: index
            )
        }
    }

    private func squaredDistance(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }

    /// Builds a region that places `coordinate` roughly 25% from the top of the
    /// screen rather than dead center, so the pin sits in the visible area above
    /// the bottom sheet instead of behind it.
    private func anchoredRegion(
        for coordinate: CLLocationCoordinate2D,
        span: MKCoordinateSpan
    ) -> MKCoordinateRegion {
        // Map center is at 50% of the height; shifting it south by 25% of the
        // latitude span moves the target coordinate up to ~25% from the top.
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func moveCamera(to region: MKCoordinateRegion) {
        guard let region = sanitized(region) else { return }
        cameraRegion = region
        visibleMapRegion = region
        cameraUpdateToken += 1
    }

    private func rebuildGTFSOnlyMapStops() {
        gtfsOnlyMapStops = gtfsMapStops.filter { gtfsStop in
            !nearbyStops.contains { liveStop in
                stopsRepresentSamePlace(liveStop, gtfsStop)
            }
        }
    }

    private func stopsRepresentSamePlace(_ lhs: Stop, _ rhs: Stop) -> Bool {
        if lhs.id == rhs.id { return true }

        let namesMatch = lhs.name.normalizedForSearch == rhs.name.normalizedForSearch
        guard namesMatch else { return false }

        return squaredDistance(from: lhs.location, to: rhs.location) < 0.000002
    }

    private func rebuildDepartureFilters() {
        let departuresMatchingLine = departuresMatchingSelectedLine()
        availableDeparturePlatforms = Array(dictOrderedSet: departuresMatchingLine.compactMap { departure in
            let platform = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines)
            return platform?.isEmpty == false ? platform : nil
        })
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        if let selectedDeparturePlatform,
           !availableDeparturePlatforms.contains(selectedDeparturePlatform) {
            self.selectedDeparturePlatform = nil
            return
        }

        filteredDepartures = departuresMatchingLine.filter { departure in
            guard let selectedDeparturePlatform else { return true }
            return departure.platform == selectedDeparturePlatform
        }
    }

    private func departuresMatchingSelectedLine() -> [Departure] {
        guard let selectedDepartureLine else { return departures }
        guard let route = selectedStopRoutes.first(where: { $0.id == selectedDepartureLine }) else {
            return departures
        }

        return departures.filter { departure in
            departure.matches(route: route)
        }
    }

    private func clearSelectedPlatformIfUnavailable() {
        guard let selectedDeparturePlatform else { return }
        if !availableDeparturePlatforms.contains(selectedDeparturePlatform) {
            self.selectedDeparturePlatform = nil
        }
    }

    private struct FavouriteDepartureBoardResult {
        let stopId: String
        let departures: [Departure]
        let didFail: Bool
        let index: Int
    }
}

private extension Departure {
    func matches(route: TransitRoute) -> Bool {
        if routeId?.caseInsensitiveCompare(route.id) == .orderedSame {
            return true
        }

        if lineName.caseInsensitiveCompare(route.shortName) == .orderedSame {
            return true
        }

        return false
    }
}

private extension [String] {
    init(dictOrderedSet values: [String]) {
        var seen: Set<String> = []
        self = values.filter { seen.insert($0).inserted }
    }
}
