import Foundation

extension TransitMapViewModel {
    var routeRealtimeRequest: RouteRealtimeRequest? {
        guard !isCalculatingRoute, !isLoadingEarlierRoutes, !isLoadingLaterRoutes,
              let origin = routeRequestOrigin,
              let destination = effectiveRouteDestination?.location,
              let option = selectedRouteOption, !option.transitLegs.isEmpty
        else { return nil }
        return .init(optionID: option.id, generation: routeCalculationGeneration,
                     origin: origin, destination: destination)
    }

    /// A single user-requested refresh of the journey shown in route detail.
    func refreshSelectedRouteRealtime(using service: any RouteService) async {
        guard let refresher = service as? any RouteRealtimeRefreshing,
              let request = routeRealtimeRequest else { return }
        routeStatusMessage = nil
        await refreshRouteRealtime(using: refresher, request: request)
    }

    func refreshRouteRealtime(using service: any RouteRealtimeRefreshing, request: RouteRealtimeRequest) async {
        do {
            guard let calculation = try await service.refreshRouteRealtime(optionID: request.optionID,
                from: request.origin, to: request.destination, refreshPolicy: .forceRefresh),
                  !Task.isCancelled, routeRealtimeRequest == request else { return }
            let invalidated = calculation.invalidatedOptionIDs.contains(request.optionID)
            let updated = calculation.allOptions.first { $0.id == request.optionID }
            guard invalidated || updated != nil else { return }
            // Merge only the requested route. Paging, ranking and other alternatives
            // belong to the last route search and must not change on a detail refresh.
            func replacingSelected(in options: [RouteOption]) -> [RouteOption] {
                options.compactMap { option in
                    guard option.id == request.optionID else { return option }
                    return invalidated ? nil : updated
                }
            }
            unfilteredRouteOptions = replacingSelected(in: unfilteredRouteOptions)
            unfilteredSupplementalRouteOptions = replacingSelected(in: unfilteredSupplementalRouteOptions)
            routeOptions = replacingSelected(in: routeOptions)
            supplementalRouteOptions = replacingSelected(in: supplementalRouteOptions)
            if invalidated {
                invalidatedRouteOptionIDs.insert(request.optionID)
                applyRouteOptions(preferredID: nil, announceFallback: true)
            }
        } catch is CancellationError {
            // A newer calculation or selection owns the displayed route now.
        } catch {
            guard routeRealtimeRequest == request else { return }
            routeStatusMessage = "Live data could not be refreshed. Showing the last available information."
        }
    }
}
