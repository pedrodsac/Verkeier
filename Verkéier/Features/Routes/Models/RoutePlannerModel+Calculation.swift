import CoreLocation
import MobiliteitKit
import OSLog

extension RoutePlannerModel {
    func calculateRoute(
        using routeService: any RouteService,
        from location: CLLocation?,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy = .useCache
    ) async {
        guard !Task.isCancelled else { return }
        guard let destination = routeDestination else {
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

        routeRequestOrigin = origin
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
                realtimeRefreshPolicy: realtimeRefreshPolicy
            )
            for try await calculation in updates {
                guard requestGeneration == routeCalculationGeneration else { return }
                invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
                let incomingOptions =
                    calculation.isAuthoritativeSnapshot
                    ? calculation.options
                    : preservingWalkingRefinements(
                        in: calculation.options,
                        existing: unfilteredRouteOptions
                    ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                let incomingSupplementalOptions =
                    calculation.isAuthoritativeSnapshot
                    ? calculation.supplementalOptions
                    : preservingWalkingRefinements(
                        in: calculation.supplementalOptions,
                        existing: unfilteredSupplementalRouteOptions
                    ).filter { !invalidatedRouteOptionIDs.contains($0.id) }
                routeBrowsingWindow = calculation.browsingWindow
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
                        origin: routeOrigin,
                        destination: destination
                    )
                }
                let walkingOnly =
                    calculation.options.count == 1
                    && calculation.options.first?.isWalkingOnly == true
                canLoadEarlierRoutes = calculation.canLoadEarlier ?? !walkingOnly
                canLoadLaterRoutes = calculation.canLoadLater ?? !walkingOnly
                receivedRouteUpdate = true
                routeLoadingPhase = calculation.hasMoreOptions ? .calculating : .idle
                if !calculation.hasMoreOptions {
                    recordRoutePublication(calculation)
                }
            }
            try Task.checkCancellation()
            guard receivedRouteUpdate else { throw RoutingError.noRouteFound }
        } catch is CancellationError {
            // Cancellation is not evidence that a journey is unavailable.
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            if receivedRouteUpdate {
                routeStatusMessage = nil
                routeErrorMessage = nil
            } else if let routingError = error as? RoutingError,
                routingError == .noPublicTransportRoute
            {
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

    /// A user retry must not disappear behind an automatic calculation or page
    /// request. Share repeated pulls and keep the operation independent of the
    /// refresh control's task lifetime.
    func refreshRoutes(using service: any RouteService, from location: CLLocation?) async {
        if let routeRefreshTask {
            await routeRefreshTask.value
            return
        }
        guard routeDestination != nil else { return }
        let generation = routeCalculationGeneration
        let task = Task {
            defer { routeRefreshTask = nil }
            while isCalculatingRoute || isLoadingEarlierRoutes || isLoadingLaterRoutes {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard generation == routeCalculationGeneration else { return }
            }
            // Endpoint, filter, or time changes invalidate a queued retry.
            guard generation == routeCalculationGeneration else { return }
            await calculateRoute(using: service, from: location, realtimeRefreshPolicy: .forceRefresh)
        }
        routeRefreshTask = task
        await task.value
    }

    func failRouteLocationRequest() {
        clearRouteResult()
        routeLoadingPhase = .idle
        routeErrorMessage = "Current location is required to calculate a route."
    }

    func startRouteRequest() -> Int {
        routeCalculationGeneration += 1
        return routeCalculationGeneration
    }

    func routeCalculationUpdatesWithDeadline(
        using routeService: any RouteService,
        from origin: LocationPoint,
        to destination: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage = .initial
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
                        page: page
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
}

// MARK: - Publishing options

extension RoutePlannerModel {
    func applyRouteOptions(preferredID: String?, announceFallback: Bool) {
        if let baseline = routePagingBaseline {
            // Restore listed routes as shown; only journeys a page added may
            // change, and a new journey can never hide a listed one.
            unfilteredRouteOptions =
                baseline.primary
                + unfilteredRouteOptions.filter { !baseline.ids.contains($0.id) }
            unfilteredSupplementalRouteOptions =
                baseline.supplemental
                + unfilteredSupplementalRouteOptions.filter { !baseline.ids.contains($0.id) }
        }
        let visible = RouteOptionVisibility.presentedOptions(
            primary: unfilteredRouteOptions,
            supplemental: unfilteredSupplementalRouteOptions,
            at: now()
        )
        if let baseline = routePagingBaseline {
            routeOptions = baseline.visiblePrimary + visible.primary.filter { !baseline.ids.contains($0.id) }
            supplementalRouteOptions =
                baseline.visibleSupplemental
                + visible.supplemental.filter { !baseline.ids.contains($0.id) }
        } else {
            routeOptions = visible.primary
            supplementalRouteOptions = visible.supplemental
        }
        selectBestRouteOption(preferredID: preferredID, announceFallback: announceFallback)
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
        selectedRouteOptionID =
            JourneySelectionPolicy.select(
                preferred: preferredID.map(JourneySignature.init),
                recommended: routeRecommendedOptionID.map(JourneySignature.init),
                candidates: allOptions.map { option in
                    (.init(option.id), JourneyStatus(rawValue: option.status(at: now()).rawValue) ?? .scheduledOnly)
                }
            )?.value
        if announceFallback, previous != nil, previous != selectedRouteOptionID {
            routeStatusMessage = "Showing the next available route."
        }
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

// MARK: - Diagnostics

extension RoutePlannerModel {
    func recordRoutePublication(_ calculation: RouteCalculation) {
        routeDiagnostics = calculation.diagnostics
        routePublishedAt = ContinuousClock.now
        if let started = routeOperationStarted {
            routeDiagnostics?.rebase(to: started)
            let publicationStart = started.advanced(
                by: .nanoseconds(Int64((calculation.diagnostics?.totalMilliseconds ?? 0) * 1_000_000))
            )
            routeDiagnostics?.record(.publication, since: publicationStart)
            routeDiagnostics?.totalMilliseconds = RoutingDiagnostics.elapsed(since: started)
        }
    }

    /// Called after the result sheet has participated in a display refresh.
    func recordRouteResultsRendered(_ requestID: UUID) {
        guard routeDiagnostics?.requestID == requestID,
            routeDiagnostics?.milliseconds[.firstRender] == nil,
            !isCalculatingRoute, !isLoadingEarlierRoutes, !isLoadingLaterRoutes, let published = routePublishedAt,
            let started = routeOperationStarted
        else { return }
        routeDiagnostics?.record(.firstRender, since: published)
        routeDiagnostics?.totalMilliseconds = RoutingDiagnostics.elapsed(since: started)
        let logger = Logger(subsystem: "dev.pedrocordeiro.Verkeier", category: "RoutePerformance")
        logger.info(
            "Route \(requestID) visible options=\(self.routeOptions.count) total_ms=\(self.routeDiagnostics?.totalMilliseconds ?? 0) stages=\(String(describing: self.routeDiagnostics?.milliseconds))"
        )
    }
}
