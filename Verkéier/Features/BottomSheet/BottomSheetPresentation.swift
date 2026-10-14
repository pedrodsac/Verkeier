import CoreLocation
import Foundation

struct TransitSheetPresentationModel {
    let favourites: FavouritesPresentationModel
    let commute: CommuteDashboardViewModel
    let route: RoutePresentationModel
    let lineDetail: LineDetailPresentationModel
    var tripDetail: TripDetailViewModel? = nil
}

struct TransitSheetActions {
    let calculateRoute: () -> Void
    let refreshRouteRealtime: () async -> Void
    let openSpecialEvent: (SpecialEvent) -> Void
    let openRouteInAppleMaps: () -> Void
    let selectRouteOrigin: (RoutePlace?) -> Void
    let selectRouteDestination: (RoutePlace) -> Void
    let applyCommutePreset: (String) -> Void
    let applyAndCalculatePreset: (String) -> Void
    let saveCurrentCommutePreset: (String) -> Void
    let swapRouteEndpoints: () -> Void
    let showRoutePlaceSearch: (RouteEndpoint) -> Void
    let updateRouteFilters: (RoutePlannerFilters) -> Void
    let setRoutePlanningTime: (RoutePlanningTime) -> Void
    let loadEarlierRoutes: () -> Void
    let loadLaterRoutes: () -> Void
    let selectLineDetailDirection: (String) -> Void
    let refreshLineDetail: () async -> Void
    let favourites: FavouritesActions
    var refreshTripDetail: () async -> Void = {}
    var refreshRoutes: () async -> Void = {}
    var maintainRoutes: () async -> Void = {}
}

struct NearbyStopsPresentationModel {
    let stops: [Stop]
    let isLoading: Bool
    let errorMessage: String?
    let referenceLocation: CLLocation?
    /// Lines serving each stop, keyed by stop id, shown on the nearby rows.
    var routesByStopId: [String: [TransitRoute]] = [:]
    var walkingEstimatesByStopID: [String: OfflineWalkingEstimate] = [:]
}
