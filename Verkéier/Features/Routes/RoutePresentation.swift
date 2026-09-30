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
    var supplementalRouteOptions: [RouteOption] = []
    var isLoadingEarlierRoutes = false
    var isLoadingLaterRoutes = false
    var canLoadEarlierRoutes = true
    var canLoadLaterRoutes = true
    let alerts: [AlertMessage]
    /// Active disruptions affecting each transit leg, keyed by leg index string.
    var legAlerts: [String: [AlertMessage]] = [:]
    let selectedRouteOptionID: String?
    let loadingPhase: RouteLoadingPhase
    let errorMessage: String?
    let statusMessage: String?
    var lastCalculatedAt: Date? = nil
    var diagnosticRequestID: UUID? = nil
    var resultsRendered: (UUID) -> Void = { _ in }

    var selectedRouteOption: RouteOption? {
        let allOptions = routeOptions + supplementalRouteOptions
        guard !allOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
           let match = allOptions.first(where: { $0.id == selectedRouteOptionID }) {
            return match
        }
        return allOptions.first
    }

    var selectedRoutePlan: RoutePlan? {
        selectedRouteOption?.plan
    }

    var chronologicallyOrderedRouteOptions: [RouteOption] {
        routeOptions.sorted { lhs, rhs in
            let lhsDeparture = lhs.departureTime ?? .distantFuture
            let rhsDeparture = rhs.departureTime ?? .distantFuture
            if lhsDeparture != rhsDeparture { return lhsDeparture < rhsDeparture }
            let lhsArrival = lhs.arrivalTime ?? .distantFuture
            let rhsArrival = rhs.arrivalTime ?? .distantFuture
            if lhsArrival != rhsArrival { return lhsArrival < rhsArrival }
            return lhs.id < rhs.id
        }
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
    var loadEarlierRoutes: () -> Void = {}
    var loadLaterRoutes: () -> Void = {}
}

extension RouteActions {
    init(from actions: TransitSheetActions) {
        self.init()
        calculateRoute = actions.calculateRoute
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
        loadEarlierRoutes = actions.loadEarlierRoutes
        loadLaterRoutes = actions.loadLaterRoutes
    }
}
