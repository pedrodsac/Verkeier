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
        guard !routeOptions.isEmpty else { return nil }
        if let selectedRouteOptionID,
           let match = routeOptions.first(where: { $0.id == selectedRouteOptionID }) {
            return match
        }
        return routeOptions.first
    }

    var visibleRouteOptions: [RouteOption] {
        Array(routeOptions.prefix(visibleRouteOptionCount))
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

        let requestGeneration = startRouteRequest()
        routeLoadingPhase = .calculating
        routeErrorMessage = nil
        routeStatusMessage = nil
        do {
            let calculation = try await routeService.calculateRoute(
                from: origin, to: destination.location, time: routePlanningTime, filters: routeFilters
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            unfilteredRouteOptions = calculation.options
            applyRouteOptions(preferredID: calculation.selectedOptionID, announceFallback: false)
            if !calculation.options.isEmpty {
                routeLastCalculatedAt = now()
                recentTrips = RoutePlannerStore.shared.recordRecentTrip(
                    origin: routeOrigin, destination: destination
                )
            }
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            if routeOptions.isEmpty {
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

    func failRouteLocationRequest() {
        clearRouteResult()
        routeLoadingPhase = .idle
        routeErrorMessage = "Current location is required to calculate a route."
    }

    @discardableResult
    func selectRouteOption(id: String) -> Bool {
        guard routeOptions.contains(where: { $0.id == id }) else { return false }
        selectedRouteOptionID = id
        routeStatusMessage = nil
        return true
    }

    func showMoreRouteOptions() {
        guard !routeOptions.isEmpty else { return }

        if visibleRouteOptionCount < routeOptions.count {
            visibleRouteOptionCount = min(routeOptions.count, visibleRouteOptionCount + 3)
            routeStatusMessage = nil
        }
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

    private func selectBestRouteOption(preferredID: String?, announceFallback: Bool) {
        guard !routeOptions.isEmpty else {
            selectedRouteOptionID = nil
            return
        }

        let viableStatuses: Set<RouteOptionStatus> = [.viable, .scheduledOnly, .atRisk]
        let optionsByID = Dictionary(uniqueKeysWithValues: routeOptions.map { ($0.id, $0) })

        if let preferredID,
           let preferred = optionsByID[preferredID],
           viableStatuses.contains(preferred.status(at: now())) {
            selectedRouteOptionID = preferredID
            return
        }

        if let replacement = routeOptions.first(where: { viableStatuses.contains($0.status(at: now())) }) {
            let changed = replacement.id != preferredID
            selectedRouteOptionID = replacement.id
            if announceFallback, changed, preferredID != nil {
                routeStatusMessage = "Showing the next available route."
            }
            return
        }

        selectedRouteOptionID = routeOptions.first?.id
    }

    private func applyRouteOptions(preferredID: String?, announceFallback: Bool) {
        let filtered = filteredRouteOptions(from: unfilteredRouteOptions)
        let didRelaxFilters = filtered.isEmpty && !unfilteredRouteOptions.isEmpty
        routeOptions = (didRelaxFilters ? unfilteredRouteOptions : filtered)
            .sorted(by: compareRouteOptions)
        visibleRouteOptionCount = min(routeOptionInitialVisibleCount, routeOptions.count)
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)

        if didRelaxFilters {
            routeStatusMessage = "No routes matched all filters. Showing the closest alternatives."
        } else if routeOptions.isEmpty {
            routeStatusMessage = nil
        }
    }

    private func filteredRouteOptions(from options: [RouteOption]) -> [RouteOption] {
        options.filter { option in
            if routeFilters.avoidTightTransfers, option.status(at: now()) == .atRisk {
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

        switch routeFilters.sort {
        case .fastest:
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        case .fewestTransfers:
            if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        case .leastWalking:
            let lhsWalking = lhs.walkingDistanceMeters
            let rhsWalking = rhs.walkingDistanceMeters
            if lhsWalking != rhsWalking { return lhsWalking < rhsWalking }
            let lhsTime = lhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            let rhsTime = rhs.plan.expectedTravelTime ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
        }

        return lhs.id < rhs.id
    }

    private func isSeverelyUnusable(_ option: RouteOption) -> Bool {
        option.transitLegs.contains {
            $0.liveStatus == .cancelled || $0.transferWarning == "Connection may be missed"
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
