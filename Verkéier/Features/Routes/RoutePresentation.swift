import Foundation

enum RouteEndpoint: Hashable {
    case origin
    case destination

    var searchTitle: String {
        switch self {
        case .origin:
            "Search Origin"
        case .destination:
            "Search Destination"
        }
    }

    var searchPrompt: String {
        switch self {
        case .origin:
            "Search origin"
        case .destination:
            "Search destination"
        }
    }
}

struct RoutePresentationModel {
    let selectedStop: Stop?
    let origin: RoutePlace?
    let destination: RoutePlace?
    let currentLocation: RoutePlace?
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
    var lastCalculatedAt: Date? = nil

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

    func selectedPlace(for endpoint: RouteEndpoint) -> RoutePlace? {
        switch endpoint {
        case .origin:
            origin
        case .destination:
            destination ?? selectedStop.map { RoutePlace(stop: $0, source: .selectedStop) }
        }
    }

    func recentPlacesExcludingPinned(for endpoint: RouteEndpoint) -> [RoutePlace] {
        let pinnedIDs = Set(
            [currentLocation?.id, selectedPlace(for: endpoint)?.id].compactMap { $0 }
        )
        return recentPlaces.filter { !pinnedIDs.contains($0.id) }
    }

    var visibleRouteOptions: [RouteOption] {
        Array(routeOptions.prefix(visibleRouteOptionCount))
    }

    var canShowMoreRouteOptions: Bool {
        visibleRouteOptionCount < routeOptions.count
    }

    var isStale: Bool {
        guard planningTime.isNow,
              let lastCalculatedAt,
              !routeOptions.isEmpty
        else {
            return false
        }
        return Date.now.timeIntervalSince(lastCalculatedAt) > 90
    }
}

/// Callbacks the route-planner sheet needs, sliced from ``TransitSheetActions``.
struct RouteActions {
    var calculateRoute: () -> Void = {}
    var showMoreRouteOptions: () -> Void = {}
    var openInAppleMaps: () -> Void = {}
    var selectRouteOrigin: (RoutePlace?) -> Void = { _ in }
    var selectRouteDestination: (RoutePlace) -> Void = { _ in }
    var applyCommutePreset: (String) -> Void = { _ in }
    var applyAndCalculatePreset: (String) -> Void = { _ in }
    var saveCurrentCommutePreset: (String) -> Void = { _ in }
    var swapRouteEndpoints: () -> Void = {}
    var showRoutePlaceSearch: (RouteEndpoint) -> Void = { _ in }
    var updateRouteFilters: (RoutePlannerFilters) -> Void = { _ in }
    var setRoutePlanningTime: (RoutePlanningTime) -> Void = { _ in }
}

extension RouteActions {
    init(from actions: TransitSheetActions) {
        self.init()
        calculateRoute = actions.calculateRoute
        showMoreRouteOptions = actions.showMoreRouteOptions
        openInAppleMaps = actions.openRouteInAppleMaps
        selectRouteOrigin = actions.selectRouteOrigin
        selectRouteDestination = actions.selectRouteDestination
        applyCommutePreset = actions.applyCommutePreset
        applyAndCalculatePreset = actions.applyAndCalculatePreset
        saveCurrentCommutePreset = actions.saveCurrentCommutePreset
        swapRouteEndpoints = actions.swapRouteEndpoints
        showRoutePlaceSearch = actions.showRoutePlaceSearch
        updateRouteFilters = actions.updateRouteFilters
        setRoutePlanningTime = actions.setRoutePlanningTime
    }
}
