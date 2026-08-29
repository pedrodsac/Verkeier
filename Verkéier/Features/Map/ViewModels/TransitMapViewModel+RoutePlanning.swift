import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    var routePlan: RoutePlan? {
        selectedRouteOption?.plan
    }

    var routeMapOverlay: RouteMapOverlay? {
        selectedRouteOption?.mapOverlay
    }

    var activeMapOverlay: RouteMapOverlay? {
        selectedLineDetail?.mapOverlay ?? routeMapOverlay
    }

    var isWaitingForRouteLocation: Bool {
        routeLoadingPhase.isWaitingForLocation
    }

    var isCalculatingRoute: Bool {
        routeLoadingPhase.isCalculating
    }

    var areRouteResultsStale: Bool {
        guard routePlanningTime.isNow,
              let routeLastCalculatedAt,
              !routeOptions.isEmpty
        else {
            return false
        }
        return now().timeIntervalSince(routeLastCalculatedAt) > 90
    }

    var selectedRouteOption: RouteOption? {
        let allOptions = routeOptions + supplementalRouteOptions
        guard !allOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
           let match = allOptions.first(where: { $0.id == selectedRouteOptionID }) {
            return match
        }
        return allOptions.first
    }

    func loadRoutePlanner(using store: RoutePlannerStore = .shared) {
        recentRoutePlaces = store.recentPlaces()
        commutePresets = store.commutePresets()
        recentStops = store.recentStops()
        recentTrips = store.recentTrips()
    }

    /// A commute preset to highlight on the home sheet based on the time of day:
    /// in the morning window (06:00–10:30) the first "Home → Work" preset, in the
    /// evening window (16:00–20:00) the last "Work → Home" preset. `nil` outside
    /// those windows or when no matching preset exists.
    var suggestedCommutePreset: RouteCommutePreset? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now())
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let minutesOfDay = hour * 60 + minute

        if (360 ... 630).contains(minutesOfDay) {
            return commutePresets.first { titleHasOrder($0.title, "Home", "Work") }
        }
        if (960 ... 1200).contains(minutesOfDay) {
            return commutePresets.last { titleHasOrder($0.title, "Work", "Home") }
        }
        return nil
    }

    /// True when `title` contains both keywords and `first` appears before `second`.
    private func titleHasOrder(_ title: String, _ first: String, _ second: String) -> Bool {
        let lower = title.lowercased()
        guard let firstRange = lower.range(of: first.lowercased()),
              let secondRange = lower.range(of: second.lowercased()) else { return false }
        return firstRange.lowerBound < secondRange.lowerBound
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
        let preset = commutePresets.first(where: { $0.id == presetID })
            ?? recentTrips.first(where: { $0.id == presetID })
        guard let preset else { return }
        routeOrigin = preset.origin
        routeDestination = preset.destination
        recentRoutePlaces = store.recordRecentPlace(preset.destination)
        clearRoute()
    }

    func saveCurrentCommutePreset(title customTitle: String = "", using store: RoutePlannerStore = .shared) {
        guard let destination = effectiveRouteDestination else { return }

        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = if !trimmed.isEmpty {
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

    func swapRouteEndpoints() {
        guard let destination = effectiveRouteDestination else { return }
        let previousOrigin = routeOrigin
        routeOrigin = destination
        routeDestination = previousOrigin
        clearRoute()
    }

    func updateRouteFilters(_ filters: RoutePlannerFilters) {
        routeFilters = filters
        applyRouteOptions(preferredID: selectedRouteOptionID, announceFallback: true)
    }

    func setRoutePlanningTime(_ time: RoutePlanningTime) {
        guard routePlanningTime != time else { return }
        routePlanningTime = time
        clearRoute()
    }

    func calculateRoute(using routeService: any RouteService, from location: CLLocation?) async {
        guard let destination = effectiveRouteDestination else {
            routeLoadingPhase = .idle
            routeErrorMessage = "Choose a route destination first."
            return
        }

        let origin: LocationPoint
        if let routeOrigin {
            origin = routeOrigin.location
        } else {
            guard let location else {
                clearRouteResult()
                routeLoadingPhase = .waitingForLocation
                routeErrorMessage = nil
                return
            }

            origin = LocationPoint(
                name: "Current Location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }

        if routeOrigin == nil, location == nil {
            clearRouteResult()
            routeLoadingPhase = .waitingForLocation
            routeErrorMessage = nil
            return
        }

        resetRoutePagingState()
        let requestGeneration = startRouteRequest()
        routeLoadingPhase = .calculating
        routeErrorMessage = nil
        routeStatusMessage = nil
        do {
            let calculation = try await routeService.calculateRoute(
                from: origin,
                to: destination.location,
                time: routePlanningTime,
                filters: routeFilters,
                realtimeRefreshPolicy: .forceRefresh
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            unfilteredRouteOptions = calculation.options
            supplementalRouteOptions = calculation.supplementalOptions
            applyRouteOptions(preferredID: calculation.selectedOptionID, announceFallback: false)
            if !calculation.allOptions.isEmpty {
                routeLastCalculatedAt = now()
                recentTrips = RoutePlannerStore.shared.recordRecentTrip(
                    origin: routeOrigin, destination: destination
                )
            }
            if calculation.options.count == 1,
               calculation.options.first?.isWalkingOnly == true {
                canLoadEarlierRoutes = false
                canLoadLaterRoutes = false
            }
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            if routeOptions.isEmpty, supplementalRouteOptions.isEmpty {
                clearRouteResult()
            } else {
                routeStatusMessage = "Routes could not be refreshed. Showing the last available results."
            }
            routeErrorMessage = routeErrorMessage(for: error)
        }

        if requestGeneration == routeCalculationGeneration {
            routeLoadingPhase = .idle
        }
    }

    func loadEarlierRoutes(using routeService: any RouteService, from location: CLLocation?) async {
        await loadRoutePage(.earlier, using: routeService, from: location)
    }

    func loadLaterRoutes(using routeService: any RouteService, from location: CLLocation?) async {
        await loadRoutePage(.later, using: routeService, from: location)
    }

    private func loadRoutePage(
        _ direction: RoutePagingDirection,
        using routeService: any RouteService,
        from location: CLLocation?
    ) async {
        guard !isLoadingEarlierRoutes, !isLoadingLaterRoutes else { return }
        guard direction == .earlier ? canLoadEarlierRoutes : canLoadLaterRoutes else { return }
        guard let destination = effectiveRouteDestination else { return }

        let origin: LocationPoint
        if let routeOrigin {
            origin = routeOrigin.location
        } else if let location {
            origin = LocationPoint(
                name: "Current Location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } else {
            routeStatusMessage = "Current location is required to load more routes."
            return
        }

        // The all-the-way walk is not schedule-based and must never move a
        // transit page boundary.
        let departures = routeOptions
            .filter { !$0.transitLegs.isEmpty }
            .compactMap(\.departureTime)
        guard let boundary = direction == .earlier ? departures.min() : departures.max() else {
            return
        }
        let page: RouteSearchPage = switch direction {
        case .earlier: .earlier(than: boundary, limit: 3)
        case .later: .later(than: boundary, limit: 3)
        }
        let requestGeneration = startRouteRequest()
        setRoutePageLoading(true, direction: direction)
        routeStatusMessage = nil

        do {
            let calculation = try await routeService.calculateRoute(
                from: origin,
                to: destination.location,
                time: routePlanningTime,
                filters: routeFilters,
                realtimeRefreshPolicy: .forceRefresh,
                page: page
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            let preferredID = selectedRouteOptionID
            unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                existing: unfilteredRouteOptions,
                incoming: calculation.options,
                invalidatedOptionIDs: calculation.invalidatedOptionIDs
            )
            applyRouteOptions(preferredID: preferredID, announceFallback: true)
            // A partial page does not prove there are no more routes. Keep paging
            // available until a search actually returns an empty page.
            setRoutePageAvailable(!calculation.options.isEmpty, direction: direction)
            routeLastCalculatedAt = now()
        } catch is CancellationError {
            // A newer full search or page request owns the visible result set.
        } catch let error as RoutingError where error == .noPublicTransportRoute {
            guard requestGeneration == routeCalculationGeneration else { return }
            setRoutePageAvailable(false, direction: direction)
            routeStatusMessage = direction == .earlier
                ? "No earlier routes were found within six hours."
                : "No later routes were found within six hours."
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            routeStatusMessage = direction == .earlier
                ? "Earlier routes could not be loaded."
                : "Later routes could not be loaded."
        }

        if requestGeneration == routeCalculationGeneration {
            setRoutePageLoading(false, direction: direction)
        }
    }

    func failRouteLocationRequest() {
        clearRouteResult()
        routeLoadingPhase = .idle
        routeErrorMessage = "Current location is required to calculate a route."
    }

    @discardableResult
    func selectRouteOption(id: String) -> Bool {
        guard (routeOptions + supplementalRouteOptions).contains(where: { $0.id == id }) else {
            return false
        }
        selectedRouteOptionID = id
        routeStatusMessage = nil
        return true
    }

    func openSelectedRouteInAppleMaps(
        using routeService: any RouteService, from location: CLLocation?
    ) {
        guard let destination = effectiveRouteDestination else { return }

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

    private var effectiveRouteDestination: RoutePlace? {
        routeDestination ?? selectedStop.map { RoutePlace(stop: $0, source: .selectedStop) }
    }

    private func startRouteRequest() -> Int {
        routeCalculationGeneration += 1
        return routeCalculationGeneration
    }

    static func mergingAccumulatedOptions(
        existing: [RouteOption],
        incoming: [RouteOption],
        invalidatedOptionIDs: Set<String>
    ) -> [RouteOption] {
        var incomingByID = Dictionary(
            incoming.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var merged: [RouteOption] = []
        var seenIDs: Set<String> = []

        for existingOption in existing {
            guard !invalidatedOptionIDs.contains(existingOption.id) else { continue }
            let option = incomingByID.removeValue(forKey: existingOption.id) ?? existingOption
            if seenIDs.insert(option.id).inserted {
                merged.append(option)
            }
        }
        for option in incoming where incomingByID[option.id] != nil {
            if seenIDs.insert(option.id).inserted {
                merged.append(option)
            }
        }
        return merged
    }

    private func selectBestRouteOption(preferredID: String?, announceFallback: Bool) {
        let allOptions = Self.chronologicallyOrderedOptions(routeOptions) + supplementalRouteOptions
        guard !allOptions.isEmpty else {
            selectedRouteOptionID = nil
            return
        }

        let viableStatuses: Set<RouteOptionStatus> = [.viable, .partiallyLive, .scheduledOnly, .atRisk]
        // Route calculations normally deduplicate options before publication, but
        // keep selection resilient to equivalent options arriving from a fallback
        // or an older route-service implementation.
        let optionsByID = Dictionary(allOptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        if let preferredID,
           let preferred = optionsByID[preferredID],
           viableStatuses.contains(preferred.status(at: now())) {
            selectedRouteOptionID = preferredID
            return
        }

        if let replacement = allOptions.first(where: { viableStatuses.contains($0.status(at: now())) }) {
            let changed = replacement.id != preferredID
            selectedRouteOptionID = replacement.id
            if announceFallback, changed, preferredID != nil {
                routeStatusMessage = "Showing the next available route."
            }
            return
        }

        selectedRouteOptionID = allOptions.first?.id
    }

    private func applyRouteOptions(preferredID: String?, announceFallback: Bool) {
        let filtered = filteredRouteOptions(from: unfilteredRouteOptions)
        let didRelaxFilters = filtered.isEmpty && !unfilteredRouteOptions.isEmpty
        routeOptions = Self.removingStrictlyDominatedOptions(
            Self.uniqueRouteOptionsByDeparture(
                uniqueRouteOptions(didRelaxFilters ? unfilteredRouteOptions : filtered)
            )
        )
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)

        if didRelaxFilters {
            routeStatusMessage = "No routes matched all filters. Showing the closest alternatives."
        } else if routeOptions.isEmpty {
            routeStatusMessage = nil
        }
    }

    static func removingStrictlyDominatedOptions(_ options: [RouteOption]) -> [RouteOption] {
        options.filter { candidate in
            guard let candidateDeparture = candidate.departureTime,
                  let candidateArrival = candidate.arrivalTime else {
                return true
            }
            return !options.contains { other in
                guard other.id != candidate.id,
                      let otherDeparture = other.departureTime,
                      let otherArrival = other.arrivalTime else {
                    return false
                }
                return otherDeparture > candidateDeparture && otherArrival < candidateArrival
            }
        }
    }

    static func uniqueRouteOptionsByDeparture(_ options: [RouteOption]) -> [RouteOption] {
        var bestByDeparture: [Int: RouteOption] = [:]
        var withoutDeparture: [RouteOption] = []
        for option in options {
            guard let departure = option.departureTime else {
                withoutDeparture.append(option)
                continue
            }
            let key = Int(departure.timeIntervalSince1970.rounded())
            if let existing = bestByDeparture[key] {
                if routeOptionRanksBefore(option, existing) {
                    bestByDeparture[key] = option
                }
            } else {
                bestByDeparture[key] = option
            }
        }
        let deduplicated = options.compactMap { option -> RouteOption? in
            guard let departure = option.departureTime else { return nil }
            let key = Int(departure.timeIntervalSince1970.rounded())
            guard bestByDeparture[key]?.id == option.id else { return nil }
            bestByDeparture[key] = nil
            return option
        }
        return deduplicated + withoutDeparture
    }

    static func chronologicallyOrderedOptions(_ options: [RouteOption]) -> [RouteOption] {
        options.sorted { lhs, rhs in
            let lhsDeparture = lhs.departureTime ?? .distantFuture
            let rhsDeparture = rhs.departureTime ?? .distantFuture
            if lhsDeparture != rhsDeparture { return lhsDeparture < rhsDeparture }
            return routeOptionRanksBefore(lhs, rhs)
        }
    }

    private static func routeOptionRanksBefore(_ lhs: RouteOption, _ rhs: RouteOption) -> Bool {
        let lhsArrival = lhs.arrivalTime ?? .distantFuture
        let rhsArrival = rhs.arrivalTime ?? .distantFuture
        if lhsArrival != rhsArrival { return lhsArrival < rhsArrival }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkingDistanceMeters != rhs.walkingDistanceMeters {
            return lhs.walkingDistanceMeters < rhs.walkingDistanceMeters
        }
        return lhs.id < rhs.id
    }

    private func setRoutePageLoading(_ loading: Bool, direction: RoutePagingDirection) {
        switch direction {
        case .earlier: isLoadingEarlierRoutes = loading
        case .later: isLoadingLaterRoutes = loading
        }
    }

    private func setRoutePageAvailable(_ available: Bool, direction: RoutePagingDirection) {
        switch direction {
        case .earlier: canLoadEarlierRoutes = available
        case .later: canLoadLaterRoutes = available
        }
    }

    private func uniqueRouteOptions(_ options: [RouteOption]) -> [RouteOption] {
        var seenIDs: Set<String> = []
        return options.filter { seenIDs.insert($0.id).inserted }
    }

    private func filteredRouteOptions(from options: [RouteOption]) -> [RouteOption] {
        options.filter { option in
            if option.isWalkingOnly { return true }

            if routeFilters.avoidTightTransfers,
               [.atRisk, .connectionMayBeMissed].contains(option.status(at: now())) {
                return false
            }

            if routeFilters.preferAccessible {
                let walkingDistance = option.walkingDistanceMeters
                if walkingDistance > 700 || option.transferCount > 1 {
                    return false
                }
            }

            guard let mode = routeFilters.modePreference.transportMode else {
                return true
            }
            return option.transitLegs.contains(where: { $0.mode == mode })
        }
    }

    private func compareRouteOptions(_ lhs: RouteOption, _ rhs: RouteOption) -> Bool {
        if case let .arriveBy(deadline) = routePlanningTime {
            let lhsSevere = isSeverelyUnusable(lhs)
            let rhsSevere = isSeverelyUnusable(rhs)
            if lhsSevere != rhsSevere { return rhsSevere }

            let lhsArrival = lhs.arrivalTime ?? .distantFuture
            let rhsArrival = rhs.arrivalTime ?? .distantFuture
            let lhsOnTime = lhsArrival <= deadline
            let rhsOnTime = rhsArrival <= deadline
            if lhsOnTime != rhsOnTime { return lhsOnTime }
            if !lhsOnTime {
                let lhsLateness = lhsArrival.timeIntervalSince(deadline)
                let rhsLateness = rhsArrival.timeIntervalSince(deadline)
                if lhsLateness != rhsLateness { return lhsLateness < rhsLateness }
            }

            let lhsDeparture = lhs.departureTime ?? .distantPast
            let rhsDeparture = rhs.departureTime ?? .distantPast
            if lhsDeparture != rhsDeparture { return lhsDeparture > rhsDeparture }
        }

        let preferredMode = routeFilters.modePreference.transportMode
        let lhsModeRank = preferredMode.map { mode in
            lhs.transitLegs.contains(where: { $0.mode == mode }) ? 0 : 1
        } ?? 0
        let rhsModeRank = preferredMode.map { mode in
            rhs.transitLegs.contains(where: { $0.mode == mode }) ? 0 : 1
        } ?? 0
        if lhsModeRank != rhsModeRank {
            return lhsModeRank < rhsModeRank
        }

        let lhsArrival = lhs.arrivalTime ?? .distantFuture
        let rhsArrival = rhs.arrivalTime ?? .distantFuture
        if lhsArrival != rhsArrival { return lhsArrival < rhsArrival }

        return lhs.id < rhs.id
    }

    private func isSeverelyUnusable(_ option: RouteOption) -> Bool {
        option.transitLegs.contains {
            $0.liveStatus == .cancelled || $0.transferWarning == "Connection miss"
        }
    }

    private func routeErrorMessage(for error: Error) -> String {
        guard let routingError = error as? RoutingError else {
            return "A public transport route could not be calculated."
        }

        switch routingError {
        case .timetableUnavailable:
            return "Public transport schedules are not available yet."
        case .noPublicTransportRoute, .noRouteFound:
            return "No public transport route was found."
        }
    }
}

private enum RoutePagingDirection {
    case earlier
    case later
}
