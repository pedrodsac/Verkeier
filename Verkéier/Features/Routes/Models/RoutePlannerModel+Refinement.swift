import Foundation
import MobiliteitKit

extension RoutePlannerModel {
    /// Refine walking geometry and timing after the full timetable and live
    /// calculation is available.
    func scheduleWalkingRouteRefinement(
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
            from: refiner.refinementEvents(
                in: primary,
                context: calculation.validationContext
            ),
            supplemental: false,
            routeService: routeService,
            origin: origin,
            destination: destination,
            requestGeneration: requestGeneration
        )
        scheduleWalkingRouteRefinementUpdates(
            from: refiner.refinementEvents(
                in: supplemental,
                context: calculation.validationContext
            ),
            supplemental: true,
            routeService: routeService,
            origin: origin,
            destination: destination,
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
        pendingWalkingRefinements[requestGeneration, default: 0] += 1
        Task { [weak self] in
            let refinementStarted = ContinuousClock.now
            defer {
                if let self {
                    let remaining = self.pendingWalkingRefinements[requestGeneration, default: 0] - 1
                    if remaining > 0 {
                        self.pendingWalkingRefinements[requestGeneration] = remaining
                    } else {
                        self.pendingWalkingRefinements.removeValue(forKey: requestGeneration)
                    }
                    if requestGeneration == self.routeCalculationGeneration {
                        self.routeDiagnostics?.record(.refinement, since: refinementStarted)
                    }
                }
            }
            for await event in updates {
                guard !Task.isCancelled,
                    let self,
                    requestGeneration == self.routeCalculationGeneration
                else {
                    return
                }

                let selectedID = self.selectedRouteOptionID
                if case let .calculation(calculation) = event {
                    self.routeBrowsingWindow = calculation.browsingWindow ?? self.routeBrowsingWindow
                    self.routeRecommendedOptionID = calculation.selectedOptionID
                    self.unfilteredRouteOptions = calculation.options
                    self.unfilteredSupplementalRouteOptions = calculation.supplementalOptions
                    self.invalidatedRouteOptionIDs.formUnion(calculation.invalidatedOptionIDs)
                    self.canLoadEarlierRoutes = calculation.canLoadEarlier ?? self.canLoadEarlierRoutes
                    self.canLoadLaterRoutes = calculation.canLoadLater ?? self.canLoadLaterRoutes
                    self.applyRouteOptions(
                        preferredID: selectedID ?? calculation.selectedOptionID,
                        announceFallback: true
                    )
                    self.scheduleWalkingRouteRefinement(
                        calculation,
                        using: routeService,
                        from: origin,
                        to: destination,
                        requestGeneration: requestGeneration
                    )
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
                    !self.invalidatedRouteOptionIDs.contains(option.id)
                else { continue }
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
}
