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
    let showRouteOptions: () -> Void
    let showSettings: () -> Void
    let toggleFavourite: () -> Void
    let toggleFavouriteExpansion: (String) -> Void
    let refreshDepartures: () -> Void
    let refreshAlerts: () -> Void
    let calculateRoute: () -> Void
    let selectRouteOption: (String) -> Void
    let showMoreRouteOptions: () -> Void
    let openRouteInAppleMaps: () -> Void
    let trackDeparture: (Departure) -> Void
    let toggleDepartureLine: (TransitRoute) -> Void
    let selectDeparturePlatform: (String?) -> Void
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
    let availablePlatforms: [String]
    let selectedLine: String?
    let selectedPlatform: String?
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
    let routeOptions: [RouteOption]
    let selectedRouteOptionID: String?
    let visibleRouteOptionCount: Int
    let loadingPhase: RouteLoadingPhase
    let errorMessage: String?
    let statusMessage: String?

    var selectedRouteOption: RouteOption? {
        guard !routeOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
           let match = routeOptions.first(where: { $0.id == selectedRouteOptionID }) {
            return match
        }
        return routeOptions.first
    }

    var selectedRoutePlan: RoutePlan? {
        selectedRouteOption?.plan
    }

    var isWaitingForLocation: Bool {
        loadingPhase.isWaitingForLocation
    }

    var isCalculating: Bool {
        loadingPhase.isCalculating
    }

    var visibleRouteOptions: [RouteOption] {
        Array(routeOptions.prefix(visibleRouteOptionCount))
    }
}

struct AlertsPresentationModel {
    let alerts: [AlertMessage]
    let isLoading: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
}
