import Foundation

/// Pure mapping shared by initial journeys and every subsequent refinement.
nonisolated enum RouteMapOverlayBuilder {
    static func itinerary(legs: [RoutePlan.Leg]) -> RouteMapOverlay {
        let segments = legs.compactMap { leg -> RouteMapSegment? in
            guard leg.mapCoordinates.count >= 2 else { return nil }
            return RouteMapSegment(id: leg.id, mode: leg.mode, routeName: leg.routeName,
                routeId: leg.routeId, coordinates: leg.mapCoordinates,
                isApproximate: leg.transportKind == .walking && leg.walkingEvidence == .estimate ? true : nil,
                routeShortName: leg.routeShortName)
        }
        let rides = legs.enumerated().filter { $0.element.transportKind == .transit || $0.element.transportKind == .bikeShare }
        var markers: [RouteMapStopMarker] = []
        for (rideIndex, indexedLeg) in rides.enumerated() {
            let leg = indexedLeg.element
            let stops = occurrences(for: leg)
            let continuation = leg.continuesInSeatFromTripID != nil
            let continuesAfter = rideIndex + 1 < rides.count && rides[rideIndex + 1].element.continuesInSeatFromTripID != nil
            for (index, stop) in stops.enumerated() {
                let role: RouteMapStopMarker.Role
                if index == 0 {
                    role = rideIndex == 0 ? .boarding : continuation ? .intermediate : .transfer
                } else if index == stops.count - 1 {
                    role = rideIndex == rides.count - 1 ? .alighting : continuesAfter ? .intermediate : .transfer
                } else {
                    role = .intermediate
                }
                let marker = RouteMapStopMarker(id: "\(leg.id):\(stop.id)", stopID: stop.stopID,
                    name: stop.name, coordinate: stop.coordinate, segmentIDs: [leg.id], mode: leg.mode, role: role)
                // Only merge the boundary of adjacent rides, never visits within a loop.
                if index == 0, rideIndex > 0, let previous = markers.last,
                   indexedLeg.offset == rides[rideIndex - 1].offset + 1,
                   previous.segmentIDs.contains(rides[rideIndex - 1].element.id),
                   previous.coordinate == marker.coordinate, previous.stopID == marker.stopID {
                    markers[markers.count - 1] = RouteMapStopMarker(id: previous.id, stopID: marker.stopID,
                        name: marker.name, coordinate: marker.coordinate,
                        segmentIDs: previous.segmentIDs + marker.segmentIDs, mode: marker.mode,
                        role: continuation ? .intermediate : .transfer)
                } else {
                    markers.append(marker)
                }
            }
        }
        return RouteMapOverlay(segments: segments, stopMarkers: markers)
    }

    static func line(segment: RouteMapSegment, stops: [RouteStopOccurrence]) -> RouteMapOverlay {
        RouteMapOverlay(segments: [segment], stopMarkers: stops.enumerated().map { index, stop in
            RouteMapStopMarker(id: "\(segment.id):\(stop.id)", stopID: stop.stopID, name: stop.name,
                coordinate: stop.coordinate, segmentIDs: [segment.id], mode: segment.mode,
                role: index == 0 || index == stops.count - 1 ? .terminus : .intermediate)
        })
    }

    static func trip(segments: [RouteMapSegment], stops: [TripStopEntry], selection: TripDetailSelection) -> RouteMapOverlay {
        let hasRide = segments.contains { $0.id == "your-ride" }
        let markers = stops.enumerated().map { index, entry in
            let inRide = selection.boardingSequence...selection.alightingSequence ~= entry.sequence
            let role: RouteMapStopMarker.Role
            if entry.sequence == selection.boardingSequence { role = .boarding }
            else if entry.sequence == selection.alightingSequence { role = .alighting }
            else if index == 0 || index == stops.count - 1 { role = .terminus }
            else { role = .intermediate }
            return RouteMapStopMarker(id: "trip:\(entry.sequence)", stopID: entry.stop.id,
                name: entry.stop.name, coordinate: RouteMapCoordinate(entry.stop.location),
                segmentIDs: [inRide && hasRide ? "your-ride" : "full-run"], mode: selection.mode,
                role: role, emphasis: inRide ? .highlighted : .context)
        }
        return RouteMapOverlay(segments: segments, stopMarkers: markers)
    }

    private static func occurrences(for leg: RoutePlan.Leg) -> [RouteStopOccurrence] {
        if let stops = leg.mapStops { return stops }
        // Older plans still have genuine endpoint stops, but no intermediate visits.
        return [("board", leg.originStopId, leg.origin), ("alight", leg.destinationStopId, leg.destination)]
            .compactMap { id, stopID, point in
                guard let stopID, let name = point.name else { return nil }
                return RouteStopOccurrence(id: id, stopID: stopID, name: name, coordinate: RouteMapCoordinate(point))
            }
    }
}
