import CoreLocation
import MapKit
import MobiliteitKit
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
        walkingRefinedOptionIDs = []
        walkingRefinementScheduledIDs = []
        invalidatedRouteOptionIDs = []
        let requestGeneration = startRouteRequest()
        routeOperationStarted = ContinuousClock.now
        routeDiagnostics = nil
        routePublishedAt = nil
        routeLoadingPhase = .calculating
        routeErrorMessage = nil
        routeStatusMessage = nil
        let manualSelectionID = routeSelectionWasManual ? selectedRouteOptionID : nil
        var receivedRouteUpdate = false
        var didScheduleWalkingRefinement = false
        do {
            let updates = routeCalculationUpdatesWithDeadline(
                using: routeService,
                from: origin,
                to: destination.location,
                time: routePlanningTime,
                filters: routeFilters,
                realtimeRefreshPolicy: .forceRefresh
            )
            for try await calculation in updates {
                guard requestGeneration == routeCalculationGeneration else { return }
                invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
                let incomingOptions = calculation.isAuthoritativeSnapshot ? calculation.options : preservingWalkingRefinements(
                    in: calculation.options,
                    existing: unfilteredRouteOptions
                ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                let incomingSupplementalOptions = calculation.isAuthoritativeSnapshot ? calculation.supplementalOptions : preservingWalkingRefinements(
                    in: calculation.supplementalOptions,
                    existing: unfilteredSupplementalRouteOptions
                ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                routeRecommendedOptionID = calculation.selectedOptionID
                let preferredID = manualSelectionID ?? calculation.selectedOptionID
                if !receivedRouteUpdate || calculation.isAuthoritativeSnapshot {
                    unfilteredRouteOptions = incomingOptions
                    unfilteredSupplementalRouteOptions = incomingSupplementalOptions
                } else {
                    unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                        existing: unfilteredRouteOptions,
                        incoming: incomingOptions,
                        invalidatedOptionIDs: invalidatedRouteOptionIDs
                    )
                    unfilteredSupplementalRouteOptions = Self.mergingAccumulatedOptions(
                        existing: unfilteredSupplementalRouteOptions,
                        incoming: incomingSupplementalOptions,
                        invalidatedOptionIDs: invalidatedRouteOptionIDs
                    )
                }
                applyRouteOptions(preferredID: preferredID, announceFallback: false)
                if !didScheduleWalkingRefinement, !calculation.hasMoreOptions {
                    didScheduleWalkingRefinement = true
                    scheduleWalkingRouteRefinement(
                        calculation,
                        using: routeService,
                        from: origin,
                        to: destination.location,
                        requestGeneration: requestGeneration
                    )
                }

                if !receivedRouteUpdate, !calculation.allOptions.isEmpty {
                    routeLastCalculatedAt = now()
                    recentTrips = RoutePlannerStore.shared.recordRecentTrip(
                        origin: routeOrigin, destination: destination
                    )
                }
                let walkingOnly = calculation.options.count == 1
                    && calculation.options.first?.isWalkingOnly == true
                canLoadEarlierRoutes = calculation.canLoadEarlier ?? !walkingOnly
                canLoadLaterRoutes = calculation.canLoadLater ?? !walkingOnly
                receivedRouteUpdate = true
                routeLoadingPhase = calculation.hasMoreOptions ? .calculating : .idle
                if !calculation.hasMoreOptions {
                    recordRoutePublication(calculation)
                }
            }
            guard receivedRouteUpdate else { throw RoutingError.noRouteFound }
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            if receivedRouteUpdate {
                routeStatusMessage = nil
                routeErrorMessage = nil
            } else if let routingError = error as? RoutingError,
                      routingError == .noPublicTransportRoute {
                // A completed search found no boardable service. Keeping an
                // older itinerary can keep suggesting a newly cancelled trip.
                clearRouteResult()
            } else if routeOptions.isEmpty, supplementalRouteOptions.isEmpty {
                clearRouteResult()
            } else {
                routeStatusMessage = "Routes could not be refreshed. Showing the last available results."
            }
            if !receivedRouteUpdate {
                routeErrorMessage = routeErrorMessage(for: error)
            }
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

        let page: RouteSearchPage = direction == .earlier ? .earlierAdjacent : .laterAdjacent
        let requestGeneration = startRouteRequest()
        routeOperationStarted = ContinuousClock.now
        routeDiagnostics = nil
        routePublishedAt = nil
        setRoutePageLoading(true, direction: direction)
        routeStatusMessage = nil

        do {
            let calculation = try await routeService.calculateRoute(
                from: origin,
                to: destination.location,
                time: routePlanningTime,
                filters: routeFilters,
                realtimeRefreshPolicy: .useCache,
                page: page
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
            routeRecommendedOptionID = calculation.selectedOptionID
            let preferredID = routeSelectionWasManual ? selectedRouteOptionID : calculation.selectedOptionID
            if calculation.isAuthoritativeSnapshot {
                unfilteredRouteOptions = calculation.options
                unfilteredSupplementalRouteOptions = calculation.supplementalOptions
            } else {
                unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                    existing: unfilteredRouteOptions, incoming: calculation.options,
                    invalidatedOptionIDs: calculation.invalidatedOptionIDs)
                unfilteredSupplementalRouteOptions = Self.mergingAccumulatedOptions(
                    existing: unfilteredSupplementalRouteOptions, incoming: calculation.supplementalOptions,
                    invalidatedOptionIDs: calculation.invalidatedOptionIDs)
            }
            applyRouteOptions(preferredID: preferredID, announceFallback: true)
            // A partial page does not prove there are no more routes. Keep paging
            // available until a search actually returns an empty page.
            setRoutePageAvailable((direction == .earlier ? calculation.canLoadEarlier : calculation.canLoadLater)
                ?? !calculation.options.isEmpty, direction: direction)
            scheduleWalkingRouteRefinement(calculation, using: routeService, from: origin,
                to: destination.location, requestGeneration: requestGeneration)
            routeLastCalculatedAt = now()
            recordRoutePublication(calculation)
        } catch is CancellationError {
            // A newer full search or page request owns the visible result set.
        } catch let error as RoutingError where error == .noPublicTransportRoute {
            guard requestGeneration == routeCalculationGeneration else { return }
            setRoutePageAvailable(false, direction: direction)
            routeStatusMessage = direction == .earlier
                ? "No earlier routes were found."
                : "No later routes were found."
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
        routeSelectionWasManual = true
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

    private func preservingWalkingRefinements(
        in incoming: [RouteOption],
        existing: [RouteOption]
    ) -> [RouteOption] {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return incoming.map { option in
            guard walkingRefinedOptionIDs.contains(option.id),
                  let previous = existingByID[option.id]
            else { return option }
            return option.replacingLegs(of: .walking, from: previous, preserveUpdatedTotals: true)
        }
    }

    private func routeCalculationUpdatesWithDeadline(
        using routeService: any RouteService,
        from origin: LocationPoint,
        to destination: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        let timeout = routeCalculationTimeout
        return AsyncThrowingStream<RouteCalculation, Error> { continuation in
            let timeoutTask = Task.detached {
                do {
                    try await Task.sleep(for: timeout)
                    continuation.finish(throwing: RoutingError.requestTimedOut)
                } catch {
                    // The first usable result arrived and cancelled the timer.
                }
            }
            let calculationTask = Task.detached(priority: .userInitiated) {
                do {
                    let updates = routeService.routeCalculationUpdates(
                        from: origin,
                        to: destination,
                        time: time,
                        filters: filters,
                        realtimeRefreshPolicy: realtimeRefreshPolicy,
                        page: .initial
                    )
                    var receivedUpdate = false
                    for try await calculation in updates {
                        if !receivedUpdate {
                            timeoutTask.cancel()
                            receivedUpdate = true
                        }
                        continuation.yield(calculation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                calculationTask.cancel()
                timeoutTask.cancel()
            }
        }
    }

    /// Refine walking geometry and timing after the full timetable and live
    /// calculation is available.
    private func scheduleWalkingRouteRefinement(
        _ calculation: RouteCalculation,
        using routeService: any RouteService,
        from origin: LocationPoint,
        to destination: LocationPoint,
        requestGeneration: Int
    ) {
        guard let refiner = routeService as? any WalkingRouteRefining else { return }
        let primary = calculation.options.filter { !walkingRefinementScheduledIDs.contains($0.id) }
        let supplemental = calculation.supplementalOptions.filter { !walkingRefinementScheduledIDs.contains($0.id) }
        walkingRefinementScheduledIDs.formUnion((primary + supplemental).map(\.id))
        scheduleWalkingRouteRefinementUpdates(
            from: refiner.refinementEvents(in: primary,
                                           context: calculation.validationContext),
            supplemental: false,
            routeService: routeService,
            origin: origin, destination: destination,
            requestGeneration: requestGeneration
        )
        scheduleWalkingRouteRefinementUpdates(
            from: refiner.refinementEvents(in: supplemental,
                                           context: calculation.validationContext),
            supplemental: true,
            routeService: routeService,
            origin: origin, destination: destination,
            requestGeneration: requestGeneration
        )
    }

    private func scheduleWalkingRouteRefinementUpdates(
        from updates: AsyncStream<WalkingRefinementEvent>,
        supplemental: Bool,
        routeService: any RouteService,
        origin: LocationPoint,
        destination: LocationPoint,
        requestGeneration: Int
    ) {
        Task { [weak self] in
            for await event in updates {
                guard !Task.isCancelled,
                      let self,
                      requestGeneration == self.routeCalculationGeneration
                else {
                    return
                }

                let selectedID = self.selectedRouteOptionID
                if case let .calculation(calculation) = event {
                    self.routeRecommendedOptionID = calculation.selectedOptionID
                    self.unfilteredRouteOptions = calculation.options
                    self.unfilteredSupplementalRouteOptions = calculation.supplementalOptions
                    self.invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
                    self.canLoadEarlierRoutes = calculation.canLoadEarlier ?? self.canLoadEarlierRoutes
                    self.canLoadLaterRoutes = calculation.canLoadLater ?? self.canLoadLaterRoutes
                    self.applyRouteOptions(preferredID: self.routeSelectionWasManual
                        ? selectedID : calculation.selectedOptionID, announceFallback: true)
                    self.scheduleWalkingRouteRefinement(calculation, using: routeService,
                        from: origin, to: destination, requestGeneration: requestGeneration)
                    continue
                }
                if case let .invalidated(id) = event {
                    self.invalidatedRouteOptionIDs.insert(id)
                    self.unfilteredRouteOptions.removeAll { $0.id == id }
                    self.unfilteredSupplementalRouteOptions.removeAll { $0.id == id }
                    self.walkingRefinedOptionIDs.remove(id)
                    self.applyRouteOptions(preferredID: selectedID, announceFallback: true)
                    continue
                }
                guard case let .option(option) = event,
                      !self.invalidatedRouteOptionIDs.contains(option.id) else { continue }
                if supplemental {
                    let current = self.unfilteredSupplementalRouteOptions.first { $0.id == option.id }
                    let refined = current.map { option.replacingLegs(of: .transit, from: $0) } ?? option
                    self.unfilteredSupplementalRouteOptions = Self.mergingAccumulatedOptions(
                        existing: self.unfilteredSupplementalRouteOptions,
                        incoming: [refined],
                        invalidatedOptionIDs: []
                    )
                } else {
                    let current = self.unfilteredRouteOptions.first { $0.id == option.id }
                    let refined = current.map { option.replacingLegs(of: .transit, from: $0) } ?? option
                    self.unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                        existing: self.unfilteredRouteOptions,
                        incoming: [refined],
                        invalidatedOptionIDs: []
                    )
                }
                self.walkingRefinedOptionIDs.insert(option.id)
                self.applyRouteOptions(preferredID: selectedID, announceFallback: false)
            }
        }
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
            if !invalidatedOptionIDs.contains(option.id), seenIDs.insert(option.id).inserted {
                merged.append(option)
            }
        }
        return merged
    }

    private func selectBestRouteOption(preferredID: String?, announceFallback: Bool) {
        let allOptions = routeOptions + supplementalRouteOptions
        let previous = selectedRouteOptionID
        selectedRouteOptionID = JourneySelectionPolicy.select(
            preferred: preferredID.map(JourneySignature.init),
            recommended: routeRecommendedOptionID.map(JourneySignature.init),
            candidates: allOptions.map { option in
                (.init(option.id), JourneyStatus(rawValue: option.status(at: now()).rawValue) ?? .scheduledOnly)
            })?.value
        if announceFallback, previous != nil, previous != selectedRouteOptionID {
            routeStatusMessage = "Showing the next available route."
        }
    }

    private func applyRouteOptions(preferredID: String?, announceFallback: Bool) {
        let visible = RouteOptionVisibility.visibleOptions(
            primary: unfilteredRouteOptions, supplemental: unfilteredSupplementalRouteOptions, at: now()
        )
        routeOptions = visible.primary
        supplementalRouteOptions = visible.supplemental
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)
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

    private func routeErrorMessage(for error: Error) -> String {
        guard let routingError = error as? RoutingError else {
            return "A public transport route could not be calculated."
        }

        switch routingError {
        case .walkingUnavailable:
            return "Walking routes are unavailable. Install the local pedestrian graph to plan a journey."
        case .timetableUnavailable:
            return "Public transport schedules are not available yet."
        case .noPublicTransportRoute, .noRouteFound:
            return "No public transport route was found."
        case .requestTimedOut:
            return "Route calculation is taking too long. Please try again."
        }
    }
}

private enum RoutePagingDirection {
    case earlier
    case later
}
