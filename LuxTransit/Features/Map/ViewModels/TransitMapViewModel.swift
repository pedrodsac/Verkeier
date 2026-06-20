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
    var routeFilters = RoutePlannerFilters()
    var recentRoutePlaces: [RoutePlace] = []
    var commutePresets: [RouteCommutePreset] = []
    var routeOptions: [RouteOption] = []
    var selectedRouteOptionID: String?
    var visibleRouteOptionCount = 0
    var routeLoadingPhase: RouteLoadingPhase = .idle
    var routeErrorMessage: String?
    var routeStatusMessage: String?
    var alerts: [AlertMessage] = []
    var isLoadingAlerts = false
    var alertsErrorMessage: String?
    var alertsLastUpdated: Date?

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.6116, longitude: 6.1319),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )
    private let minimumMapSpan = 0.001
    private let favouriteDepartureConcurrencyLimit = 3
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

    func showHome() {
        sheetContext = .home
        sheetDetent = .medium
        clearRoute()
    }

    func showSearch() {
        sheetContext = .search
        sheetDetent = .expanded
        clearRoute()
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
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
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

    func selectStop(_ stop: Stop) {
        selectedStop = stop
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
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
        moveCamera(to: MKCoordinateRegion(
            center: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func loadRoutePlanner(using store: RoutePlannerStore = .shared) {
        recentRoutePlaces = store.recentPlaces()
        commutePresets = store.commutePresets()
    }

    func selectRouteOrigin(_ place: RoutePlace?) {
        routeOrigin = place
        clearRoute()
    }

    func selectRouteDestination(_ place: RoutePlace, using store: RoutePlannerStore = .shared) {
        routeDestination = place
        recentRoutePlaces = store.recordRecentPlace(place)
        clearRoute()
    }

    func applyCommutePreset(_ presetID: String, using store: RoutePlannerStore = .shared) {
        guard let preset = commutePresets.first(where: { $0.id == presetID }) else { return }
        routeOrigin = preset.origin
        routeDestination = preset.destination
        recentRoutePlaces = store.recordRecentPlace(preset.destination)
        clearRoute()
    }

    func saveCurrentCommutePreset(using store: RoutePlannerStore = .shared) {
        guard let destination = effectiveRouteDestination else { return }

        let title: String
        if let routeOrigin {
            title = "\(routeOrigin.title) to \(destination.title)"
        } else {
            title = "Current Location to \(destination.title)"
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
        searchResults = Array(await gtfsService.searchStops(query: searchQuery).prefix(80))
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
                from: origin, to: destination.location)
            guard requestGeneration == routeCalculationGeneration else { return }
            unfilteredRouteOptions = calculation.options
            applyRouteOptions(preferredID: calculation.selectedOptionID, announceFallback: false)
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

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }

    private func clearRoute() {
        routeCalculationGeneration += 1
        clearRouteResult()
        routeErrorMessage = nil
        routeLoadingPhase = .idle
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
            if announceFallback && changed && preferredID != nil {
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
            for _ in 0..<min(favouriteDepartureConcurrencyLimit, favourites.count) {
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
            return FavouriteDepartureBoardResult(
                stopId: stop.id,
                departures: try await atpClient.departureBoards(stopIds: stop.platformIds),
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

    private struct FavouriteDepartureBoardResult: Sendable {
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

private extension Array where Element == String {
    init(dictOrderedSet values: [String]) {
        var seen: Set<String> = []
        self = values.filter { seen.insert($0).inserted }
    }
}
