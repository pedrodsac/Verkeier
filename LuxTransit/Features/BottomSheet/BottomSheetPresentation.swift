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

struct SettingsPresentationModel {
    let configuration: AppConfiguration
    let gtfsUpdateSnapshot: GTFSUpdateSnapshot
    let isCheckingGTFSUpdate: Bool
    let readiness: DataReadinessSnapshot
    let supportBundleText: String
    let debugDataMode: DebugTransitDataMode
}

struct NearbyStopsPresentationModel {
    let stops: [Stop]
    let isLoading: Bool
    let errorMessage: String?
    let referenceLocation: CLLocation?
    /// Lines serving each stop, keyed by stop id, shown on the nearby rows.
    var routesByStopId: [String: [TransitRoute]] = [:]
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
    /// Time-of-day commute preset to surface at the top of the dashboard, if any.
    var suggestedCommutePreset: RouteCommutePreset?
    /// Recently opened stops, most-recent first.
    var recentStops: [Stop] = []

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
    let referenceLocation: CLLocation?
}

struct StopDetailPresentationModel {
    let stop: Stop?
    let routes: [TransitRoute]
    let departures: [Departure]
    let offlineScheduledDepartures: [OfflineScheduleDeparture]
    let alerts: [AlertMessage]
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
    let liveActivityStaleMessage: String
    let activeReminder: SharedTrackedDepartureReminder?
    let departureReminderErrorMessage: String?
}

struct RoutePresentationModel {
    let selectedStop: Stop?
    let origin: RoutePlace?
    let destination: RoutePlace?
    let favouritePlaces: [RoutePlace]
    let nearbyPlaces: [RoutePlace]
    let recentPlaces: [RoutePlace]
    let commutePresets: [RouteCommutePreset]
    var recentTrips: [RouteCommutePreset] = []
    let filters: RoutePlannerFilters
    let planningTime: RoutePlanningTime
    let routeOptions: [RouteOption]
    let alerts: [AlertMessage]
    /// Active disruptions affecting each transit leg, keyed by leg index string.
    var legAlerts: [String: [AlertMessage]] = [:]
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

    var originTitle: String {
        origin?.title ?? "Current Location"
    }

    var originSubtitle: String? {
        origin?.subtitle ?? "Live device location"
    }

    var destinationTitle: String {
        destination?.title ?? selectedStop?.name ?? "Choose Destination"
    }

    var destinationSubtitle: String? {
        destination?.subtitle ?? selectedStop?.locality
    }

    var hasDestination: Bool {
        destination != nil || selectedStop != nil
    }

    var visibleRouteOptions: [RouteOption] {
        Array(routeOptions.prefix(visibleRouteOptionCount))
    }

    var canShowMoreRouteOptions: Bool {
        visibleRouteOptionCount < routeOptions.count
    }
}

struct LineDetailPresentationModel {
    let route: TransitRoute?
    let detail: LineDetail?
    let alerts: [AlertMessage]
    let errorMessage: String?
}

struct AlertsPresentationModel {
    let alerts: [AlertMessage]
    let isLoading: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
}
