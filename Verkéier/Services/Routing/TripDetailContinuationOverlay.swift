import Foundation

extension TripDetailSnapshot {
    nonisolated func includingContinuationOverlays() -> TripDetailSnapshot {
        var segments = mapOverlay.segments
        var markers = mapOverlay.stopMarkers
        for continuation in continuations {
            let prefix = "continuation:\(continuation.selection.instance.tripID):"
            // The onward run is context, not an extension of the selected ride.
            segments += continuation.snapshot.mapOverlay.segments.filter { $0.id == "full-run" }.map {
                .init(id: prefix + $0.id, mode: $0.mode, routeName: $0.routeName, routeId: $0.routeId,
                    coordinates: $0.coordinates, emphasis: .context,
                    isApproximate: $0.isApproximate, routeShortName: $0.routeShortName)
            }
            markers += continuation.snapshot.mapOverlay.stopMarkers.map {
                .init(id: prefix + $0.id, stopID: $0.stopID, name: $0.name, coordinate: $0.coordinate,
                    segmentIDs: [prefix + "full-run"], mode: $0.mode,
                    role: .intermediate, emphasis: .context)
            }
        }
        return .init(instance: instance, stops: stops,
            mapOverlay: .init(segments: segments, transferMarkers: mapOverlay.transferMarkers, stopMarkers: markers),
            isApproximateRoute: isApproximateRoute || continuations.contains { $0.snapshot.isApproximateRoute },
            liveDataAvailable: liveDataAvailable, isCancelled: isCancelled, fetchedAt: fetchedAt,
            continuations: continuations)
    }
}
