import Foundation
import MobiliteitKit
import OSLog

extension TransitMapViewModel {
    func recordRoutePublication(_ calculation: RouteCalculation) {
        routeDiagnostics = calculation.diagnostics
        routePublishedAt = ContinuousClock.now
        if let started = routeOperationStarted {
            routeDiagnostics?.milliseconds[.publication] = max(0,
                RoutingDiagnostics.elapsed(since: started) - (calculation.diagnostics?.totalMilliseconds ?? 0))
            routeDiagnostics?.totalMilliseconds = RoutingDiagnostics.elapsed(since: started)
        }
    }

    /// Called after the result sheet has participated in a display refresh.
    func recordRouteResultsRendered(_ requestID: UUID) {
        guard routeDiagnostics?.requestID == requestID,
              routeDiagnostics?.milliseconds[.firstRender] == nil,
              !isCalculatingRoute, !isLoadingEarlierRoutes, !isLoadingLaterRoutes, let published = routePublishedAt,
              let started = routeOperationStarted else { return }
        routeDiagnostics?.record(.firstRender, since: published)
        routeDiagnostics?.totalMilliseconds = RoutingDiagnostics.elapsed(since: started)
        let logger = Logger(subsystem: "dev.pedrocordeiro.Verkeier", category: "RoutePerformance")
        logger.info("Route \(requestID) visible options=\(self.routeOptions.count) total_ms=\(self.routeDiagnostics?.totalMilliseconds ?? 0) stages=\(String(describing: self.routeDiagnostics?.milliseconds))")
    }
}
