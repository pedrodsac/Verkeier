import Foundation
import MobiliteitKit

extension MobiliteitRouteService {
    /// Replace initially approximate walking segments after a route has been
    /// shown. Consecutive walks are routed once between their outer endpoints.
    /// Failures leave the original legs in place.
    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] {
        var refinedByID = Dictionary(
            options.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for await option in refineWalkingRouteUpdates(in: options) {
            refinedByID[option.id] = option
        }
        return options.map { refinedByID[$0.id] ?? $0 }
    }

    /// Streams walking refinements as soon as each pedestrian request completes.
    /// A single walking request can be shared by multiple alternatives, so all
    /// affected options are emitted with the completed geometry applied.
    nonisolated func refineWalkingRouteUpdates(
        in options: [RouteOption]
    ) -> AsyncStream<RouteOption> {
        let requests = options.flatMap { option in
            WalkingLegSpan.spans(in: option.plan.legs)
                .filter(\.needsRouting)
                .map(\.request)
        }
        let uniqueRequests = Dictionary(
            requests.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !uniqueRequests.isEmpty else {
            return AsyncStream { continuation in continuation.finish() }
        }

        let provider = roadRouteProvider
        let maximumConcurrentRequests = 4
        let requestsToRun = Array(uniqueRequests.values)
        return AsyncStream { continuation in
            let task = Task {
                var routesByLeg: [String: RoadRoute] = [:]
                var startIndex = 0

                while startIndex < requestsToRun.count {
                    guard !Task.isCancelled else { break }
                    let endIndex = min(startIndex + maximumConcurrentRequests, requestsToRun.count)
                    await withTaskGroup(of: (String, RoadRoute?).self) { group in
                        for request in requestsToRun[startIndex..<endIndex] {
                            group.addTask {
                                let route = await provider.roadRoute(
                                    from: request.origin,
                                    to: request.destination,
                                    transport: .walking
                                )
                                return (request.key, route)
                            }
                        }
                        for await (key, route) in group {
                            guard !Task.isCancelled,
                                  let route
                            else { continue }

                            routesByLeg[key] = route
                            for option in options where WalkingLegSpan.spans(in: option.plan.legs).contains(where: { span in
                                span.needsRouting && span.request.key == key
                            }) {
                                let refined = option.replacingWalkingRoutes(routesByLeg: routesByLeg)
                                if refined != option { continuation.yield(refined) }
                            }
                        }
                    }
                    startIndex = endIndex
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    nonisolated func refinementEvents(
        in options: [RouteOption], context: RouteValidationContext?
    ) -> AsyncStream<WalkingRefinementEvent> {
        let originals = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AsyncStream { continuation in
            let task = Task {
                for await option in refineWalkingRouteUpdates(in: options) {
                    guard !Task.isCancelled else { break }
                    do {
                        if let original = originals[option.id],
                           let result = try await sessions.submit(option, replacing: original) {
                            continuation.yield(.calculation(calculation(from: result,
                                origin: option.plan.origin, destination: option.plan.destination)))
                        } else if let context = option.validationContext ?? context {
                            let feasibility = RouteItineraryValidator.assess(option, context: context)
                            if feasibility.isInvalid { continuation.yield(.invalidated(option.id)) }
                            else {
                                var assessed = option; assessed.feasibility = feasibility
                                continuation.yield(.option(assessed))
                            }
                        } else { continuation.yield(.option(option)) }
                    } catch is CancellationError { break }
                    catch JourneyPlanningError.staleRefinement { continue }
                    catch { continue }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
