import CoreLocation
import MobiliteitKit
import Observation

/// Journey planning: endpoints, filters, saved commutes, and the route options
/// found for them. Calculation, paging, walking refinement, and live refresh
/// live in the extensions beside this file.
@MainActor @Observable
final class RoutePlannerModel {
    var routeOrigin: RoutePlace?
    var routeDestination: RoutePlace?
    var routeFilters = AppPreferences.shared.defaultRouteFilters
    var routePlanningTime: RoutePlanningTime = .leaveNow

    var recentRoutePlaces: [RoutePlace] = []
    var recentTrips: [RouteCommutePreset] = []
    var commutePresets: [RouteCommutePreset] = []

    var routeOptions: [RouteOption] = []
    var supplementalRouteOptions: [RouteOption] = []
    var routeBrowsingWindow: JourneyBrowsingWindow?
    var selectedRouteOptionID: String?
    var routeRecommendedOptionID: String? = nil
    var routeSelectionWasManual = false
    var routeLoadingPhase: RouteLoadingPhase = .idle
    var routeErrorMessage: String?
    var routeStatusMessage: String?
    var routeLastCalculatedAt: Date?
    var routeDiagnostics: RoutingDiagnostics?

    var isLoadingEarlierRoutes = false
    var isLoadingLaterRoutes = false
    var canLoadEarlierRoutes = true
    var canLoadLaterRoutes = true
    /// Set once the user pages with Earlier/Later; automatic reloads pause
    /// until a full calculation (pull to refresh, new trip) clears it.
    var routePagingBaseline: RoutePagingBaseline?

    /// The origin the current results were calculated from, kept stable while
    /// paging so a GPS update cannot start a different planning session.
    var routeRequestOrigin: LocationPoint?
    var routeCalculationGeneration = 0
    var unfilteredRouteOptions: [RouteOption] = []
    var unfilteredSupplementalRouteOptions: [RouteOption] = []
    var walkingRefinementScheduledIDs: Set<String> = []
    var walkingRefinedOptionIDs: Set<String> = []
    var invalidatedRouteOptionIDs: Set<String> = []
    @ObservationIgnored var pendingWalkingRefinements: [Int: Int] = [:]
    @ObservationIgnored var routeRefreshTask: Task<Void, Never>?
    @ObservationIgnored var routeOperationStarted: ContinuousClock.Instant?
    @ObservationIgnored var routePublishedAt: ContinuousClock.Instant?

    let routeCalculationTimeout: Duration
    let now: @Sendable () -> Date

    init(
        now: @escaping @Sendable () -> Date = { .now },
        routeCalculationTimeout: Duration = .seconds(15)
    ) {
        self.now = now
        self.routeCalculationTimeout = routeCalculationTimeout
    }

    var selectedRouteOption: RouteOption? {
        let allOptions = routeOptions + supplementalRouteOptions
        guard !allOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
            let match = allOptions.first(where: { $0.id == selectedRouteOptionID })
        {
            return match
        }
        return allOptions.first
    }

    var routeMapOverlay: RouteMapOverlay? {
        selectedRouteOption?.mapOverlay
    }

    var isWaitingForRouteLocation: Bool {
        routeLoadingPhase.isWaitingForLocation
    }

    var isCalculatingRoute: Bool {
        routeLoadingPhase.isCalculating
    }

    var isBrowsingRoutePages: Bool {
        routePagingBaseline != nil
    }

    var hasPendingWalkingRefinements: Bool {
        pendingWalkingRefinements[routeCalculationGeneration, default: 0] > 0
    }

    /// A commute preset to highlight on the home sheet based on the time of day:
    /// in the morning window (06:00–10:30) the first "Home → Work" preset, in the
    /// evening window (16:00–20:00) the last "Work → Home" preset. `nil` outside
    /// those windows or when no matching preset exists.
    var suggestedCommutePreset: RouteCommutePreset? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now())
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let minutesOfDay = hour * 60 + minute

        if (360...630).contains(minutesOfDay) {
            return commutePresets.first { Self.titleHasOrder($0.title, "Home", "Work") }
        }
        if (960...1200).contains(minutesOfDay) {
            return commutePresets.last { Self.titleHasOrder($0.title, "Work", "Home") }
        }
        return nil
    }

    /// True when `title` contains both keywords and `first` appears before `second`.
    private static func titleHasOrder(_ title: String, _ first: String, _ second: String) -> Bool {
        let lower = title.lowercased()
        guard let firstRange = lower.range(of: first.lowercased()),
            let secondRange = lower.range(of: second.lowercased())
        else { return false }
        return firstRange.lowerBound < secondRange.lowerBound
    }
}

// MARK: - Endpoints and presets

extension RoutePlannerModel {
    func loadRoutePlanner(using store: RoutePlannerStore = .shared) {
        recentRoutePlaces = store.recentPlaces()
        commutePresets = store.commutePresets()
        recentTrips = store.recentTrips()
    }

    /// Plans to `stop` from the current origin, as when a stop is opened.
    func planToSelectedStop(_ stop: Stop) {
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
        routeErrorMessage = nil
        clearRoute()
    }

    func clearEndpoints() {
        routeOrigin = nil
        routeDestination = nil
        clearRoute()
    }

    func selectRouteOrigin(_ place: RoutePlace?, using store: RoutePlannerStore = .shared) {
        routeOrigin = place
        if let place {
            recentRoutePlaces = store.recordRecentPlace(place)
        }
        clearRoute()
    }

    func selectRouteDestination(_ place: RoutePlace, using store: RoutePlannerStore = .shared) {
        routeDestination = place
        recentRoutePlaces = store.recordRecentPlace(place)
        clearRoute()
    }

    func applyCommutePreset(_ presetID: String, using store: RoutePlannerStore = .shared) {
        let preset =
            commutePresets.first(where: { $0.id == presetID })
            ?? recentTrips.first(where: { $0.id == presetID })
        guard let preset else { return }
        routeOrigin = preset.origin
        routeDestination = preset.destination
        recentRoutePlaces = store.recordRecentPlace(preset.destination)
        clearRoute()
    }

    func saveCurrentCommutePreset(title customTitle: String = "", using store: RoutePlannerStore = .shared) {
        guard let destination = routeDestination else { return }

        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String =
            if !trimmed.isEmpty {
                trimmed
            } else if let routeOrigin {
                "\(routeOrigin.title) to \(destination.title)"
            } else {
                "Current Location to \(destination.title)"
            }

        let preset = RouteCommutePreset(
            title: title,
            origin: routeOrigin,
            destination: destination
        )
        var updated = commutePresets.filter {
            !($0.origin == preset.origin && $0.destination == preset.destination)
        }
        updated.insert(preset, at: 0)
        if updated.count > 6 {
            updated = Array(updated.prefix(6))
        }
        commutePresets = updated
        store.saveCommutePresets(updated)
    }

    func swapRouteEndpoints(currentLocation: RoutePlace? = nil) {
        guard let destination = routeDestination,
            let previousOrigin = routeOrigin ?? currentLocation
        else { return }
        routeOrigin = destination.source == .currentLocation ? nil : destination
        routeDestination = previousOrigin
        clearRoute()
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        guard routeFilters != filters else { return }
        routeFilters = filters
        clearRoute()
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard routePlanningTime != time else { return }
        routePlanningTime = time
        clearRoute()
    }

    @discardableResult
    func selectRouteOption(id: String) -> Bool {
        guard (routeOptions + supplementalRouteOptions).contains(where: { $0.id == id }) else {
            return false
        }
        selectedRouteOptionID = id
        routeSelectionWasManual = true
        routeStatusMessage = nil
        return true
    }

    func openSelectedRouteInAppleMaps(
        using routeService: any RouteService,
        from location: CLLocation?
    ) {
        guard let destination = routeDestination else { return }

        let origin: LocationPoint
        if let routeOrigin {
            origin = routeOrigin.location
        } else {
            guard let location else { return }
            origin = LocationPoint(
                name: "Current Location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }

        routeService.openInAppleMaps(from: origin, to: destination.location)
    }
}

// MARK: - Clearing results

extension RoutePlannerModel {
    func clearRoute() {
        routeCalculationGeneration += 1
        clearRouteResult()
        routeErrorMessage = nil
        routeLoadingPhase = .idle
    }

    func clearRouteResult() {
        routeBrowsingWindow = nil
        routeRequestOrigin = nil
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
        routePagingBaseline = nil
    }
}
