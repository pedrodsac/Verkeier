import CoreLocation
import MapKit
import Observation
import MobiliteitKit
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
    var nearbyWalkingEstimates: [String: OfflineWalkingEstimate] = [:]
    var selectedStop: Stop?
    var selectedStopRoutes: [TransitRoute] = []

    var isLoadingNearbyStops = false
    var nearbyStopsErrorMessage: String?
    var gtfsFeedStatus: GTFSFeedStatus = .unavailable
    var liveTransitLastUpdated: Date?
    var liveTransitErrorMessage: String?
    var departures: [Departure] = []

    var offlineScheduledDepartures: [OfflineScheduleDeparture] = []
    var isUsingOfflineDepartures = false
    var selectedDepartureLine: String?

    var selectedDeparturePlatform: String?

    /// Session-scoped advanced query controls for the selected stop. They are
    /// intentionally separate from the visible line/platform chips so the UI
    /// can keep common interactions lightweight.
    var departureBoardFilter = TransitBoardFilter()
    var isLoadingDepartures = false
    var departuresErrorMessage: String?
    var departuresLastUpdated: Date?
    /// Every departure request receives a generation. A response may publish
    /// only while it remains the most recent request for the selected stop.
    var departureLoadGeneration = 0
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
    var routeDiagnostics: RoutingDiagnostics?
    @ObservationIgnored var routeOperationStarted: ContinuousClock.Instant?
    @ObservationIgnored var routePublishedAt: ContinuousClock.Instant?
    var supplementalRouteOptions: [RouteOption] = []
    var isLoadingEarlierRoutes = false
    var isLoadingLaterRoutes = false
    var canLoadEarlierRoutes = true
    var canLoadLaterRoutes = true
    var selectedRouteOptionID: String?
    var routeRecommendedOptionID: String? = nil
    var routeSelectionWasManual = false
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
    let routeCalculationTimeout: Duration
    var visibleMapRegion: MKCoordinateRegion?
    var lastNearbyStopsRequestLocation: CLLocation?
    let nearbyStopsRefreshDistance: CLLocationDistance = 100
    let now: @Sendable () -> Date
    var routeCalculationGeneration = 0
    var unfilteredRouteOptions: [RouteOption] = []
    var unfilteredSupplementalRouteOptions: [RouteOption] = []
    var walkingRefinementScheduledIDs: Set<String> = []
    var walkingRefinedOptionIDs: Set<String> = []
    var invalidatedRouteOptionIDs: Set<String> = []

    init(
        now: @escaping @Sendable () -> Date = { .now },
        routeCalculationTimeout: Duration = .seconds(15)
    ) {
        self.now = now
        self.routeCalculationTimeout = routeCalculationTimeout
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
        walkingRefinedOptionIDs = []
        walkingRefinementScheduledIDs = []
        invalidatedRouteOptionIDs = []
        unfilteredRouteOptions = []
        unfilteredSupplementalRouteOptions = []
        routeOptions = []
        supplementalRouteOptions = []
        selectedRouteOptionID = nil
        routeRecommendedOptionID = nil
        routeSelectionWasManual = false
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
        // Normalize each name once. The former nested scan repeated Foundation
        // string folding for every GTFS/live pair on the main actor.
        let liveIDs = Set(nearbyStops.map(\.id))
        let liveStopsByName = Dictionary(grouping: nearbyStops) { $0.name.normalizedForSearch }
        let nextStops = gtfsMapStops.filter { gtfsStop in
            guard !liveIDs.contains(gtfsStop.id) else { return false }
            let candidates = liveStopsByName[gtfsStop.name.normalizedForSearch] ?? []
            return !candidates.contains {
                squaredDistance(from: $0.location, to: gtfsStop.location) < 0.000002
            }
        }
        if gtfsOnlyMapStops != nextStops { gtfsOnlyMapStops = nextStops }
    }

    struct FavouriteDepartureBoardResult: Sendable {
        let stopId: String
        let departures: [Departure]
        let fetchedAt: Date
        let didFail: Bool
        let usedLiveData: Bool
        let index: Int
    }
}
