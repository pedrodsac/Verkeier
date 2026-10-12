import CoreLocation

extension TransitMapViewModel {
    /// A user retry must not disappear behind an automatic calculation or page
    /// request. Share repeated pulls and keep the operation independent of the
    /// refresh control's task lifetime.
    func refreshRoutes(using service: any RouteService, from location: CLLocation?) async {
        if let routeRefreshTask {
            await routeRefreshTask.value
            return
        }
        guard effectiveRouteDestination != nil else { return }
        let generation = routeCalculationGeneration
        let task = Task {
            defer { routeRefreshTask = nil }
            while isCalculatingRoute || isLoadingEarlierRoutes || isLoadingLaterRoutes {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
                guard generation == routeCalculationGeneration else { return }
            }
            // Endpoint, filter, or time changes invalidate a queued retry.
            guard generation == routeCalculationGeneration else { return }
            await calculateRoute(using: service, from: location, realtimeRefreshPolicy: .forceRefresh)
        }
        routeRefreshTask = task
        await task.value
    }
}
