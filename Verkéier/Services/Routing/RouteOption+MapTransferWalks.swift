import Foundation

extension RouteOption {
    nonisolated func addingMapTransferWalks(routesByKey: [String: RoadRoute]) -> RouteOption {
        let segments = MapTransferWalkingRequest.requests(in: plan.legs).compactMap { request -> RouteMapSegment? in
            guard let route = routesByKey[request.geometry.key],
                  route.walkingEvidence == .routedPedestrian,
                  route.coordinates.count >= 2 else { return nil }
            return RouteMapSegment(id: request.id, mode: .walking,
                                   coordinates: route.coordinates, isApproximate: false)
        }
        guard !segments.isEmpty else { return self }
        let overlay = mapOverlay ?? RouteMapOverlayBuilder.itinerary(legs: plan.legs)
        var updated = self
        updated.mapOverlay = RouteMapOverlay(
            segments: overlay.segments.filter { !$0.id.hasPrefix(MapTransferWalkingRequest.segmentPrefix) } + segments,
            transferMarkers: overlay.transferMarkers, stopMarkers: overlay.stopMarkers)
        return updated
    }

    /// Keep decorations through shape/walking merges only while their source
    /// endpoints still match. Changed shapes must receive a newly routed path.
    nonisolated func mapTransferWalks(for legs: [RoutePlan.Leg]) -> [RouteMapSegment] {
        let ids = Set(MapTransferWalkingRequest.requests(in: legs).map(\.id))
        return mapOverlay?.segments.filter { ids.contains($0.id) } ?? []
    }
}
