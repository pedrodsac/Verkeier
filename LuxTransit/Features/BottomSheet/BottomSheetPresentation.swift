import Foundation

struct TransitSheetPresentationModel {
    let context: TransitSheetContext
    let nearby: NearbyStopsPresentationModel
    let commute: CommuteDashboardViewModel
    let search: SearchPresentationModel
    let stopDetail: StopDetailPresentationModel
    let route: RoutePresentationModel
    let alerts: AlertsPresentationModel
    let settings: SettingsPresentationModel
}

struct TransitSheetActions {
    let selectStop: (Stop) -> Void
    let showHome: () -> Void
    let showSearch: () -> Void
    let showAlerts: () -> Void
    let showStopDetail: () -> Void
    let showDirections: () -> Void
    let showSettings: () -> Void
    let toggleFavourite: () -> Void
    let toggleFavouriteExpansion: (String) -> Void
    let refreshDepartures: () -> Void
    let refreshAlerts: () -> Void
    let calculateRoute: () -> Void
    let openRouteInAppleMaps: () -> Void
    let trackDeparture: (Departure) -> Void
    let updateSearch: () -> Void
    let checkGTFSUpdate: () -> Void
}

struct SettingsPresentationModel {
    let configuration: AppConfiguration
    let gtfsUpdateSnapshot: GTFSUpdateSnapshot
    let isCheckingGTFSUpdate: Bool
}

struct NearbyStopsPresentationModel {
    let stops: [Stop]
    let isLoading: Bool
    let errorMessage: String?
}

struct CommuteDashboardViewModel {
    let favourites: [Stop]
    let departuresByStopId: [String: [Departure]]
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let expandedStopIds: Set<String>
    let nearby: NearbyStopsPresentationModel
    let activeAlertCount: Int

    var hasFavourites: Bool {
        !favourites.isEmpty
    }

    var statusText: String {
        if isLoadingDepartures && departuresByStopId.isEmpty {
            return "Loading favourite departures"
        }
        guard let lastUpdated else {
            return hasFavourites
                ? "Live departures from favourites" : "Search or pick a nearby stop"
        }
        let formatted = lastUpdated.formatted(date: .omitted, time: .shortened)
        return isStale ? "Stale, last updated \(formatted)" : "Updated \(formatted)"
    }
}

struct SearchPresentationModel {
    let results: [Stop]
    let nearbySuggestions: [Stop]
    let isLoadingNearbySuggestions: Bool
}

struct StopDetailPresentationModel {
    let stop: Stop?
    let routes: [TransitRoute]
    let departures: [Departure]
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let isFavourite: Bool
    let trackedDepartureId: String?
    let liveActivityErrorMessage: String?
}

struct RoutePresentationModel {
    let selectedStop: Stop?
    let routePlan: RoutePlan?
    let isCalculating: Bool
    let errorMessage: String?
}

struct AlertsPresentationModel {
    let alerts: [AlertMessage]
    let isLoading: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
}
