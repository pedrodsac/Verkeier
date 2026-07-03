import Foundation

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

/// Callbacks the route-planner sheet needs, sliced from ``TransitSheetActions``.
struct RouteActions {
    var calculateRoute: () -> Void = {}
    var selectRouteOption: (String) -> Void = { _ in }
    var showMoreRouteOptions: () -> Void = {}
    var openInAppleMaps: () -> Void = {}
    var selectRouteOrigin: (RoutePlace?) -> Void = { _ in }
    var selectRouteDestination: (RoutePlace) -> Void = { _ in }
    var applyCommutePreset: (String) -> Void = { _ in }
    var saveCurrentCommutePreset: (String) -> Void = { _ in }
    var swapRouteEndpoints: () -> Void = {}
    var updateRouteFilters: (RoutePlannerFilters) -> Void = { _ in }
}

extension RouteActions {
    init(from actions: TransitSheetActions) {
        self.init()
        calculateRoute = actions.calculateRoute
        selectRouteOption = actions.selectRouteOption
        showMoreRouteOptions = actions.showMoreRouteOptions
        openInAppleMaps = actions.openRouteInAppleMaps
        selectRouteOrigin = actions.selectRouteOrigin
        selectRouteDestination = actions.selectRouteDestination
        applyCommutePreset = actions.applyCommutePreset
        saveCurrentCommutePreset = actions.saveCurrentCommutePreset
        swapRouteEndpoints = actions.swapRouteEndpoints
        updateRouteFilters = actions.updateRouteFilters
    }
}
