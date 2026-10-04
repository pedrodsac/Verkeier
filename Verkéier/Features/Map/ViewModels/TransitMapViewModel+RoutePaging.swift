import CoreLocation
import Foundation

extension TransitMapViewModel {
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
        guard !isCalculatingRoute, !isLoadingEarlierRoutes, !isLoadingLaterRoutes else { return }
        guard direction == .earlier ? canLoadEarlierRoutes : canLoadLaterRoutes else { return }
        guard let destination = effectiveRouteDestination else { return }
        // Keep the original coordinate endpoint stable while browsing. A GPS
        // update must not silently create a different package planning session.
        let origin: LocationPoint
        if let fixedOrigin = routeRequestOrigin ?? routeOrigin?.location {
            origin = fixedOrigin
        } else if let location {
            origin = LocationPoint(name: "Current Location",
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } else {
            routeStatusMessage = "Current location is required to load more routes."
            return
        }

        let previousIDs = Set(unfilteredRouteOptions.map(\.id))
        let selectedID = selectedRouteOptionID
        let page: RouteSearchPage = direction == .earlier ? .earlierAdjacent : .laterAdjacent
        let requestGeneration = startRouteRequest()
        // Previous presentation tasks stop at the generation boundary. Resubmit
        // any unfinished walking spans from the next authoritative snapshot.
        walkingRefinementScheduledIDs = []
        routeOperationStarted = ContinuousClock.now
        routeDiagnostics = nil
        routePublishedAt = nil
        setRoutePageLoading(true, direction: direction)
        routeStatusMessage = nil
        var receivedUpdate = false
        do {
            let updates = routeCalculationUpdatesWithDeadline(using: routeService,
                from: origin, to: destination.location, time: routePlanningTime,
                filters: routeFilters, realtimeRefreshPolicy: .useCache, page: page)
            for try await calculation in updates {
                try Task.checkCancellation()
                guard requestGeneration == routeCalculationGeneration else { return }
                receivedUpdate = true
                invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
                routeRecommendedOptionID = calculation.selectedOptionID
                routeBrowsingWindow = calculation.browsingWindow ?? routeBrowsingWindow
                if calculation.isAuthoritativeSnapshot {
                    unfilteredRouteOptions = calculation.options
                    unfilteredSupplementalRouteOptions = calculation.supplementalOptions
                } else {
                    unfilteredRouteOptions = Self.mergingAccumulatedOptions(
                        existing: unfilteredRouteOptions, incoming: calculation.options,
                        invalidatedOptionIDs: invalidatedRouteOptionIDs)
                    unfilteredSupplementalRouteOptions = Self.mergingAccumulatedOptions(
                        existing: unfilteredSupplementalRouteOptions, incoming: calculation.supplementalOptions,
                        invalidatedOptionIDs: invalidatedRouteOptionIDs)
                }
                applyRouteOptions(preferredID: selectedID ?? calculation.selectedOptionID, announceFallback: true)
                canLoadEarlierRoutes = calculation.canLoadEarlier ?? canLoadEarlierRoutes
                canLoadLaterRoutes = calculation.canLoadLater ?? canLoadLaterRoutes
                if (direction == .earlier ? calculation.canLoadEarlier : calculation.canLoadLater) == nil {
                    setRoutePageAvailable(!calculation.options.isEmpty, direction: direction)
                }
                if !calculation.hasMoreOptions {
                    scheduleWalkingRouteRefinement(calculation, using: routeService, from: origin,
                        to: destination.location, requestGeneration: requestGeneration)
                    routeLastCalculatedAt = now()
                    recordRoutePublication(calculation)
                }
            }
            try Task.checkCancellation()
            guard requestGeneration == routeCalculationGeneration else { return }
            guard receivedUpdate else { throw RoutingError.noRouteFound }
            if Set(unfilteredRouteOptions.map(\.id)).subtracting(previousIDs).isEmpty {
                routeStatusMessage = direction == .earlier
                    ? "No earlier routes were found." : "No later routes were found."
            }
        } catch is CancellationError {
            // A newer request owns the visible result set.
        } catch let error as RoutingError where error == .noPublicTransportRoute || error == .noRouteFound {
            guard requestGeneration == routeCalculationGeneration else { return }
            setRoutePageAvailable(false, direction: direction)
            routeStatusMessage = direction == .earlier
                ? "No earlier routes were found." : "No later routes were found."
        } catch {
            guard requestGeneration == routeCalculationGeneration else { return }
            routeStatusMessage = direction == .earlier
                ? "Earlier routes could not be loaded. Try again."
                : "Later routes could not be loaded. Try again."
        }
        if requestGeneration == routeCalculationGeneration {
            setRoutePageLoading(false, direction: direction)
        }
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

}

private enum RoutePagingDirection {
    case earlier
    case later
}
