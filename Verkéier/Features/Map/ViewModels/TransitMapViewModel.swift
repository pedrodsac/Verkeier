import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class TransitMapViewModel {
    var cameraRegion: MKCoordinateRegion
    var cameraUpdateToken = 0
    var selectedStopGroup: [Stop] = []
    var selectedBikeShareStations: [BikeShareStation] = []
    var nearbyStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }

    var gtfsMapStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }

    private(set) var gtfsOnlyMapStops: [Stop] = []
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

    /// Session-scoped advanced query controls for the selected stop. They are
    /// intentionally separate from the visible line/platform chips so the UI
    /// can keep common interactions lightweight.
    var departureBoardFilter = TransitBoardFilter() {
        didSet { rebuildDepartureFilters() }
    }

    private(set) var availableDeparturePlatforms: [String] = []
    private(set) var filteredDepartures: [Departure] = []
    var isLoadingDepartures = false
    var departuresErrorMessage: String?
    var departuresLastUpdated: Date?
    var favouriteDepartureBoards: [String: FavouriteDepartureBoardSnapshot] = [:]
    var isLoadingFavouriteDepartures = false
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
    var supplementalRouteOptions: [RouteOption] = []
    var isLoadingEarlierRoutes = false
    var isLoadingLaterRoutes = false
    var canLoadEarlierRoutes = true
    var canLoadLaterRoutes = true
    var selectedRouteOptionID: String?
    var routeLoadingPhase: RouteLoadingPhase = .idle
    var routeErrorMessage: String?
    var routeStatusMessage: String?
    var routeLastCalculatedAt: Date?
    var alerts: [AlertMessage] = []
    var selectedLineDetailRoute: TransitRoute?
    var selectedLineDetailDirectionID: String?
    var selectedLineDetail: LineDetail?
    var selectedLineDetailErrorMessage: String?
    var isLoadingAlerts = false
    var alertsErrorMessage: String?
    var alertsLastUpdated: Date?

    let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.6116, longitude: 6.1319),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )
    let minimumMapSpan = 0.001
    let favouriteDepartureConcurrencyLimit = 3
    let nearbyRouteConcurrencyLimit = 10
    var visibleMapRegion: MKCoordinateRegion?
    let now: @Sendable () -> Date
    var routeCalculationGeneration = 0
    var unfilteredRouteOptions: [RouteOption] = []

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
        cameraRegion = defaultRegion
    }
    func sanitized(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
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

    func clearRoute() {
        routeCalculationGeneration += 1
        clearRouteResult()
        routeErrorMessage = nil
        routeLoadingPhase = .idle
    }

    func clearLineDetail() {
        selectedLineDetailRoute = nil
        selectedLineDetailDirectionID = nil
        selectedLineDetail = nil
        selectedLineDetailErrorMessage = nil
    }

    func clearRouteResult() {
        unfilteredRouteOptions = []
        routeOptions = []
        supplementalRouteOptions = []
        selectedRouteOptionID = nil
        routeStatusMessage = nil
        routeLastCalculatedAt = nil
        resetRoutePagingState()
    }

    func resetRoutePagingState() {
        isLoadingEarlierRoutes = false
        isLoadingLaterRoutes = false
        canLoadEarlierRoutes = true
        canLoadLaterRoutes = true
    }

    func squaredDistance(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }

    /// Builds a region that places `coordinate` roughly 25% from the top of the
    /// screen rather than dead center, so the pin sits in the visible area above
    /// the bottom sheet instead of behind it.
    func anchoredRegion(
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

    func moveCamera(to region: MKCoordinateRegion) {
        guard let region = sanitized(region) else { return }
        cameraRegion = region
        visibleMapRegion = region
        cameraUpdateToken += 1
    }

    func rebuildGTFSOnlyMapStops() {
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

    func rebuildDepartureFilters() {
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

    func clearSelectedPlatformIfUnavailable() {
        guard let selectedDeparturePlatform else { return }
        if !availableDeparturePlatforms.contains(selectedDeparturePlatform) {
            self.selectedDeparturePlatform = nil
        }
    }

    struct FavouriteDepartureBoardResult {
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
