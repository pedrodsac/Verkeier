import CoreLocation
import Foundation

struct TransitSheetPresentationModel {
    let favourites: FavouritesPresentationModel
    let commute: CommuteDashboardViewModel
}

struct TransitSheetActions {
    let openSpecialEvent: (SpecialEvent) -> Void
    let favourites: FavouritesActions
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
