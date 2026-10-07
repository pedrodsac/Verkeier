import Foundation

extension TransitMapViewModel {
    var routeRealtimeRequest: RouteRealtimeRequest? {
        guard !isCalculatingRoute, !isLoadingEarlierRoutes, !isLoadingLaterRoutes,
              let origin = routeRequestOrigin,
              let destination = effectiveRouteDestination?.location,
              (unfilteredRouteOptions + unfilteredSupplementalRouteOptions).contains(where: { !$0.transitLegs.isEmpty })
        else { return nil }
        return .init(generation: routeCalculationGeneration, origin: origin, destination: destination)
    }

    func trackRouteRealtime(using service: any RouteService, request: RouteRealtimeRequest,
                            interval: Duration = .seconds(45)) async {
        guard let refresher = service as? any RouteRealtimeRefreshing else { return }
        var first = true
        while !Task.isCancelled, routeRealtimeRequest == request {
            await refreshRouteRealtime(using: refresher, request: request,
                                       policy: first ? .useCache : .forceRefresh)
            first = false
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    func refreshRouteRealtime(using service: any RouteRealtimeRefreshing, request: RouteRealtimeRequest,
                              policy: RouteRealtimeRefreshPolicy = .useCache) async {
        do {
            guard let calculation = try await service.refreshRouteRealtime(from: request.origin,
                to: request.destination, refreshPolicy: policy),
                  !Task.isCancelled, routeRealtimeRequest == request else { return }
            let selectedID = selectedRouteOptionID
            unfilteredRouteOptions = calculation.options
            unfilteredSupplementalRouteOptions = calculation.supplementalOptions
            invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
            routeRecommendedOptionID = calculation.selectedOptionID
            routeBrowsingWindow = calculation.browsingWindow ?? routeBrowsingWindow
            canLoadEarlierRoutes = calculation.canLoadEarlier ?? canLoadEarlierRoutes
            canLoadLaterRoutes = calculation.canLoadLater ?? canLoadLaterRoutes
            applyRouteOptions(preferredID: selectedID ?? calculation.selectedOptionID, announceFallback: true)
        } catch is CancellationError {
            // Visibility or a newer calculation owns the task now.
        } catch {
            // Keep the last available result; the next interval retries.
        }
    }
}
