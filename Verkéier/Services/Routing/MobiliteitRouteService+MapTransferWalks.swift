import Foundation

extension MobiliteitRouteService {
    /// Route map decorations through the same local pedestrian graph as real
    /// walks, without submitting them to the journey planner or its timing cache.
    nonisolated func addingMapTransferWalks(to options: [RouteOption]) async -> [RouteOption] {
        let requests = options.flatMap { MapTransferWalkingRequest.requests(in: $0.plan.legs) }
        let unique = Dictionary(requests.map { ($0.geometry.key, $0.geometry) },
                                uniquingKeysWith: { first, _ in first })
        guard !unique.isEmpty else { return options }
        let geometries = Array(unique.values)
        let provider = roadRouteProvider
        var routes: [String: RoadRoute] = [:]
        for start in stride(from: 0, to: geometries.count, by: 4) {
            guard !Task.isCancelled else { return options }
            let batch = geometries[start..<min(start + 4, geometries.count)]
            await withTaskGroup(of: (String, RoadRoute?).self) { group in
                for geometry in batch {
                    group.addTask {
                        (geometry.key, await provider.roadRoute(from: geometry.origin,
                            to: geometry.destination, transport: .walking))
                    }
                }
                for await (key, route) in group {
                    guard let route, route.walkingEvidence == .routedPedestrian,
                          route.coordinates.count >= 2 else { continue }
                    routes[key] = route
                }
            }
        }
        guard !Task.isCancelled else { return options }
        return options.map { $0.addingMapTransferWalks(routesByKey: routes) }
    }
}
