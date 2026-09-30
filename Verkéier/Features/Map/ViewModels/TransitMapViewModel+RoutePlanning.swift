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
        walkingRefinedOptionIDs = []
        invalidatedRouteOptionIDs = []
        walkingReplanGeneration = nil
        routeSelectionWasManual = false
        let requestGeneration = startRouteRequest()
        routeLoadingPhase = .calculating
        routeErrorMessage = nil
        routeStatusMessage = nil
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
                let incomingOptions = preservingWalkingRefinements(
                    in: calculation.options,
                    existing: unfilteredRouteOptions
                ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                let incomingSupplementalOptions = preservingWalkingRefinements(
                    in: calculation.supplementalOptions,
                    existing: supplementalRouteOptions
                ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                let preferredID = routeSelectionWasManual
                    ? selectedRouteOptionID
                    : calculation.selectedOptionID
                if !receivedRouteUpdate {
                    unfilteredRouteOptions = incomingOptions
                    supplementalRouteOptions = incomingSupplementalOptions
                } else {
                    unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                        existing: unfilteredRouteOptions,
                        incoming: incomingOptions,
                        invalidatedOptionIDs: invalidatedRouteOptionIDs
                    )
                    supplementalRouteOptions = Self.mergingAccumulatedOptions(
                        existing: supplementalRouteOptions,
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
                canLoadEarlierRoutes = !walkingOnly
                canLoadLaterRoutes = !walkingOnly
                receivedRouteUpdate = true
                routeLoadingPhase = calculation.hasMoreOptions ? .calculating : .idle
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

        // The all-the-way walk is not schedule-based and must never move a
        // transit page boundary.
        let departures = routeOptions
            .filter { !$0.transitLegs.isEmpty }
            .compactMap { option -> (Date, String)? in
                option.departureTime.map { ($0, option.id) }
            }
        let cursor = departures.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1 < $1.1
        }
        guard let boundary = direction == .earlier ? cursor.first : cursor.last else {
            return
        }
        let page: RouteSearchPage = switch direction {
        case .earlier: .earlierFrom(than: boundary.0, id: boundary.1, limit: 3)
        case .later: .laterFrom(than: boundary.0, id: boundary.1, limit: 3)
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
                realtimeRefreshPolicy: .useCache,
                page: page
            )
            guard requestGeneration == routeCalculationGeneration else { return }
            invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
            let preferredID = selectedRouteOptionID
            unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                existing: unfilteredRouteOptions,
                incoming: calculation.options.filter { !invalidatedRouteOptionIDs.contains($0.id) },
                invalidatedOptionIDs: invalidatedRouteOptionIDs
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
        scheduleWalkingRouteRefinementUpdates(
            from: refiner.refinementEvents(in: calculation.options,
                                           context: calculation.validationContext),
            supplemental: false,
            routeService: routeService,
            origin: origin, destination: destination,
            requestGeneration: requestGeneration
        )
        scheduleWalkingRouteRefinementUpdates(
            from: refiner.refinementEvents(in: calculation.supplementalOptions,
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
                if case let .invalidated(id) = event {
                    self.invalidatedRouteOptionIDs.insert(id)
                    self.unfilteredRouteOptions.removeAll { $0.id == id }
                    self.supplementalRouteOptions.removeAll { $0.id == id }
                    self.walkingRefinedOptionIDs.remove(id)
                    self.applyRouteOptions(preferredID: selectedID, announceFallback: true)
                    if !supplemental, self.walkingReplanGeneration != requestGeneration {
                        self.walkingReplanGeneration = requestGeneration
                        await self.replanAfterWalkingInvalidation(
                            using: routeService, from: origin, to: destination,
                            requestGeneration: requestGeneration
                        )
                    }
                    continue
                }
                guard case let .option(option) = event,
                      !self.invalidatedRouteOptionIDs.contains(option.id) else { continue }
                if supplemental {
                    let current = self.supplementalRouteOptions.first { $0.id == option.id }
                    let refined = current.map { option.replacingLegs(of: .transit, from: $0) } ?? option
                    self.supplementalRouteOptions = Self.mergingAccumulatedOptions(
                        existing: self.supplementalRouteOptions,
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

    private func replanAfterWalkingInvalidation(
        using routeService: any RouteService,
        from origin: LocationPoint,
        to destination: LocationPoint,
        requestGeneration: Int
    ) async {
        let time = routePlanningTime
        let filters = routeFilters
        guard let calculation = try? await routeService.calculateRoute(
            from: origin, to: destination, time: time, filters: filters,
            realtimeRefreshPolicy: .useCache, page: .initial
        ), requestGeneration == routeCalculationGeneration else { return }
        let incoming = calculation.options.filter { !invalidatedRouteOptionIDs.contains($0.id) }
        unfilteredRouteOptions = Self.mergingAccumulatedOptions(
            existing: unfilteredRouteOptions, incoming: incoming,
            invalidatedOptionIDs: invalidatedRouteOptionIDs
        )
        applyRouteOptions(preferredID: selectedRouteOptionID, announceFallback: true)
        // One corrected-cache replan is the limit for this request generation.
        scheduleWalkingRouteRefinement(calculation, using: routeService,
                                       from: origin, to: destination,
                                       requestGeneration: requestGeneration)
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
        let allOptions = Self.chronologicallyOrderedOptions(routeOptions) + supplementalRouteOptions
        guard !allOptions.isEmpty else {
            selectedRouteOptionID = nil
            return
        }

        let viableStatuses: Set<RouteOptionStatus> = [
            .viable, .delayed, .partiallyLive, .scheduledOnly, .atRisk,
        ]
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

        if let replacement = allOptions.filter({ viableStatuses.contains($0.status(at: now())) })
            .min(by: compareRouteOptions) {
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
        routeOptions = Self.deduplicatingEquivalentRouteOptions(
            uniqueRouteOptions(didRelaxFilters ? unfilteredRouteOptions : filtered)
        )
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)

        if didRelaxFilters {
            routeStatusMessage = "No routes matched all filters. Showing the closest alternatives."
        } else if routeOptions.isEmpty {
            routeStatusMessage = nil
        } else if let preferred = routeFilters.modePreference.transportMode,
                  !routeOptions.contains(where: { $0.transitLegs.contains { $0.mode == preferred } }) {
            routeStatusMessage = "No routes using the preferred mode were found. Showing other routes."
        } else {
            routeStatusMessage = nil
        }
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

    /// Keep distinct itineraries with equal or competing times, but hide a
    /// transit journey when another usable one leaves no earlier and arrives
    /// no later, or takes the same first and last trips with an unnecessary
    /// intermediate ride. Compare actual times rather than rounded card minutes.
    static func deduplicatingEquivalentRouteOptions(_ options: [RouteOption]) -> [RouteOption] {
        var result: [RouteOption] = []
        var indexByID: [String: Int] = [:]

        for option in options {
            if let index = indexByID[option.id] {
                if transferTimingRanksBefore(option, result[index]) {
                    result[index] = option
                }
            } else {
                indexByID[option.id] = result.count
                result.append(option)
            }
        }
        return result.filter { candidate in
            guard !candidate.transitLegs.isEmpty,
                  !candidate.transitLegs.contains(where: { $0.liveStatus == .cancelled }),
                  let departure = candidate.departureTime,
                  let arrival = candidate.arrivalTime else { return true }

            return !result.contains { other in
                guard other.id != candidate.id,
                      !other.transitLegs.isEmpty,
                      other.feasibility?.isInvalid != true,
                      !other.transitLegs.contains(where: {
                          $0.liveStatus == .cancelled || $0.transferWarning == "Connection miss"
                      }),
                      let otherDeparture = other.departureTime,
                      let otherArrival = other.arrivalTime else { return false }
                let improvesTime = otherDeparture >= departure && otherArrival <= arrival
                    && (otherDeparture > departure || otherArrival < arrival)
                return improvesTime || isRedundantIntermediateRide(candidate, comparedTo: other)
            }
        }
    }

    private static func isRedundantIntermediateRide(
        _ candidate: RouteOption,
        comparedTo other: RouteOption
    ) -> Bool {
        let rides = candidate.transitLegs
        let simplerRides = other.transitLegs
        let calendar = Calendar.current
        // Small differences in walking geometry should not preserve an extra transfer.
        let maximumAdditionalWalkMeters = 50.0
        guard rides.count > 2, simplerRides.count == 2,
              let departure = candidate.departureTime,
              let simplerDeparture = other.departureTime,
              calendar.isDate(departure, equalTo: simplerDeparture, toGranularity: .minute),
              let arrival = candidate.arrivalTime,
              let simplerArrival = other.arrivalTime,
              calendar.isDate(arrival, equalTo: simplerArrival, toGranularity: .minute),
              candidate.walkingDistanceMeters + maximumAdditionalWalkMeters >= other.walkingDistanceMeters,
              let firstTrip = rides.first?.tripId,
              let lastTrip = rides.last?.tripId,
              firstTrip == simplerRides.first?.tripId,
              lastTrip == simplerRides.last?.tripId,
              let boardingStop = rides.first?.originStopId,
              let alightingStop = rides.last?.destinationStopId,
              boardingStop == simplerRides.first?.originStopId,
              alightingStop == simplerRides.last?.destinationStopId
        else { return false }
        return true
    }

    private static func transferTimingRanksBefore(_ lhs: RouteOption, _ rhs: RouteOption) -> Bool {
        let lhsIsDirect = lhs.transferCount == 0
        let rhsIsDirect = rhs.transferCount == 0
        if lhsIsDirect != rhsIsDirect { return lhsIsDirect }

        let lhsGaps = lhs.transferGapDurations
        let rhsGaps = rhs.transferGapDurations
        if (lhsGaps != nil) != (rhsGaps != nil) { return lhsGaps != nil }

        if let lhsMinimum = lhsGaps?.min(), let rhsMinimum = rhsGaps?.min(),
           lhsMinimum != rhsMinimum {
            return lhsMinimum > rhsMinimum
        }

        if let lhsTotal = lhsGaps?.reduce(0, +), let rhsTotal = rhsGaps?.reduce(0, +),
           lhsTotal != rhsTotal {
            return lhsTotal > rhsTotal
        }

        return routeOptionRanksBefore(lhs, rhs)
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

            return true
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

        let anchor = routePlanningTime.date ?? now()
        let lhsTime = max(0, (lhs.arrivalTime ?? .distantFuture).timeIntervalSince(anchor))
        let rhsTime = max(0, (rhs.arrivalTime ?? .distantFuture).timeIntervalSince(anchor))
        let lhsScore = lhsTime + Double(lhs.transferCount) * 300
            + lhs.plan.legs.filter { $0.transportKind == .walking }.reduce(0) {
                $0 + max(0, ($1.arrivalTime ?? .distantPast).timeIntervalSince($1.departureTime ?? .distantPast))
            }
        let rhsScore = rhsTime + Double(rhs.transferCount) * 300
            + rhs.plan.legs.filter { $0.transportKind == .walking }.reduce(0) {
                $0 + max(0, ($1.arrivalTime ?? .distantPast).timeIntervalSince($1.departureTime ?? .distantPast))
            }
        if lhsScore != rhsScore { return lhsScore < rhsScore }

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
        case .requestTimedOut:
            return "Route calculation is taking too long. Please try again."
        }
    }
}

private enum RoutePagingDirection {
    case earlier
    case later
}
