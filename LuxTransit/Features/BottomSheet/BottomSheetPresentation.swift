import CoreLocation
import Foundation

struct TransitSheetPresentationModel {
    let context: TransitSheetContext
    let nearby: NearbyStopsPresentationModel
    let commute: CommuteDashboardViewModel
    let search: SearchPresentationModel
    let stopDetail: StopDetailPresentationModel
    let route: RoutePresentationModel
    let lineDetail: LineDetailPresentationModel
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
    let showLineDetail: (TransitRoute) -> Void
    let selectLineDetailDirection: (String) -> Void
    let showSettings: () -> Void
    let toggleFavourite: () -> Void
    let toggleFavouriteExpansion: (String) -> Void
    let refreshDepartures: () async -> Void
    let refreshAlerts: () -> Void
    let calculateRoute: () -> Void
    let selectRouteOption: (String) -> Void
    let showMoreRouteOptions: () -> Void
    let openRouteInAppleMaps: () -> Void
    let selectRouteOrigin: (RoutePlace?) -> Void
    let selectRouteDestination: (RoutePlace) -> Void
    let applyCommutePreset: (String) -> Void
    let saveCurrentCommutePreset: (String) -> Void
    let swapRouteEndpoints: () -> Void
    let updateRouteFilters: (RoutePlannerFilters) -> Void
    let setRoutePlanningTime: (RoutePlanningTime) -> Void
    let startTrackingDeparture: (Departure) -> Void
    let stopTrackingDeparture: () -> Void
    let scheduleDepartureReminder: (Departure, Int) -> Void
    let cancelDepartureReminder: () -> Void
    let toggleDepartureLine: (TransitRoute) -> Void
    let selectDeparturePlatform: (String?) -> Void
    let updateSearch: () -> Void
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void
    let setMapModeFilter: (TransportMode?) -> Void
}

struct NearbyStopsPresentationModel {
    let stops: [Stop]
    let isLoading: Bool
    let errorMessage: String?
    let referenceLocation: CLLocation?
    /// Lines serving each stop, keyed by stop id, shown on the nearby rows.
    var routesByStopId: [String: [TransitRoute]] = [:]
}

// MARK: - Search

struct SearchPresentationModel {
    let results: [Stop]
    let nearbySuggestions: [Stop]
    let isLoadingNearbySuggestions: Bool
    let referenceLocation: CLLocation?
}

/// Callbacks the search sheet needs, sliced from ``TransitSheetActions``.
struct SearchActions {
    var updateSearch: () -> Void = {}
    var selectStop: (Stop) -> Void = { _ in }
    var cancel: () -> Void = {}
}

extension SearchActions {
    init(from actions: TransitSheetActions) {
        self.init()
        updateSearch = actions.updateSearch
        selectStop = actions.selectStop
        cancel = actions.showHome
    }
}

// MARK: - Alerts

struct AlertsPresentationModel {
    let alerts: [AlertMessage]
    let isLoading: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
}

// MARK: - Settings

struct SettingsPresentationModel {
    let configuration: AppConfiguration
    let gtfsUpdateSnapshot: GTFSUpdateSnapshot
    let isCheckingGTFSUpdate: Bool
    let readiness: DataReadinessSnapshot
    let supportBundleText: String
    let debugDataMode: DebugTransitDataMode
}
