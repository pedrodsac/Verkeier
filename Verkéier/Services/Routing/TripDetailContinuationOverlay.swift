import Foundation

extension TripDetailSnapshot {
    nonisolated func includingContinuationOverlays(highlighting rides: [TripDetailSelection] = []) -> TripDetailSnapshot
    {
        var segments = mapOverlay.segments
        var markers = mapOverlay.stopMarkers
        for continuation in continuations {
            let prefix = "continuation:\(continuation.selection.instance.tripID):"
            let isInJourney = rides.contains { $0.instance == continuation.selection.instance }
            segments += continuation.snapshot.mapOverlay.segments.filter { $0.id == "full-run" || isInJourney }.map {
                .init(
                    id: prefix + $0.id,
                    mode: $0.mode,
                    routeName: $0.routeName,
                    routeId: $0.routeId,
                    coordinates: $0.coordinates,
                    emphasis: isInJourney ? $0.emphasis : .context,
                    isApproximate: $0.isApproximate,
                    routeShortName: $0.routeShortName
                )
            }
            markers += continuation.snapshot.mapOverlay.stopMarkers.map {
                .init(
                    id: prefix + $0.id,
                    stopID: $0.stopID,
                    name: $0.name,
                    coordinate: $0.coordinate,
                    segmentIDs: isInJourney ? $0.segmentIDs.map { prefix + $0 } : [prefix + "full-run"],
                    mode: $0.mode,
                    role: isInJourney ? $0.role : .intermediate,
                    emphasis: isInJourney ? $0.emphasis : .context
                )
            }
        }
        return .init(
            instance: instance,
            stops: stops,
            mapOverlay: .init(segments: segments, transferMarkers: mapOverlay.transferMarkers, stopMarkers: markers),
            isApproximateRoute: isApproximateRoute || continuations.contains { $0.snapshot.isApproximateRoute },
            liveDataAvailable: liveDataAvailable,
            isCancelled: isCancelled,
            fetchedAt: fetchedAt,
            continuations: continuations
        )
    }
}
