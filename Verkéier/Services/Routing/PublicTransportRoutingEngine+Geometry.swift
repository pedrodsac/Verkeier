import CoreLocation
import Foundation
import MapKit

extension PublicTransportRoutingEngine {
    nonisolated func destinationStopMatches(
        for point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double
    ) -> [StopCandidate] {
        let normalizedName = point.name?.normalizedForSearch
        let searchRadius = max(radiusMeters, 2500)
        var nearbyStopsByID = Dictionary(
            uniqueKeysWithValues: context.nearbyStops(to: point, radiusMeters: searchRadius).map { ($0.id, $0) }
        )
        if let exactStop = context.stopsById[point.id] {
            nearbyStopsByID[exactStop.id] = exactStop
        }
        let matches = nearbyStopsByID.values.compactMap { stop -> StopCandidate? in
            let geometricDistance = routeSearchDistanceMeters(from: point, to: stop.location)
            let walkingDistance = context.walkingDistanceMeters(from: point, to: stop.location)
            let idMatches = stop.id == point.id
            let nameMatches = normalizedName?.isEmpty == false
                && stop.name.normalizedForSearch == normalizedName
                && geometricDistance <= 2500
            let distanceMatches = walkingDistance <= radiusMeters

            guard idMatches || nameMatches || distanceMatches else { return nil }
            return StopCandidate(stop: stop, distanceMeters: idMatches ? 0 : walkingDistance)
        }

        return matches
            .sorted {
                if $0.distanceMeters != $1.distanceMeters {
                    return $0.distanceMeters < $1.distanceMeters
                }
                return $0.stop.name.localizedStandardCompare($1.stop.name) == .orderedAscending
            }
            .prefix(10)
            .map(\.self)
    }

    nonisolated func scheduledTransitLeg(
        sequence: Int,
        trip: GTFSTimetableTripEntry,
        route: GTFSTimetableRouteEntry,
        boardTime: GTFSTimetableStopTimeEntry,
        alightTime: GTFSTimetableStopTimeEntry,
        boardStop: GTFSTimetableStopEntry,
        alightStop: GTFSTimetableStopEntry,
        context: RouteSearchContext
    ) -> RoutePlan.Leg {
        let departure = date(seconds: boardTime.departureSeconds, from: context.serviceStart)
        let arrival = date(seconds: alightTime.arrivalSeconds, from: context.serviceStart)
        let routeName = route.shortName.isEmpty ? route.longName : route.shortName
        let stopCount = trip.stopTimes.filter {
            $0.sequence > boardTime.sequence && $0.sequence <= alightTime.sequence
        }.count
        let destinationName = alightTime.headsign?.stationDisplayName
            ?? trip.headsign?.stationDisplayName
            ?? alightStop.name.stationDisplayName
        let coordinates: [RouteMapCoordinate]
        let roadRoutingHint: RouteLegRoadRoutingHint
        if route.transportMode == .bus,
           let shapeCoordinates = shapeCoordinates(
               trip: trip,
               boardTime: boardTime,
               alightTime: alightTime,
               boardStop: boardStop,
               alightStop: alightStop,
               context: context
           ) {
            coordinates = shapeCoordinates
            roadRoutingHint = .none
        } else if route.transportMode == .bus {
            coordinates = stopCoordinates(
                trip: trip,
                fromSequence: boardTime.sequence,
                toSequence: alightTime.sequence,
                context: context
            )
            roadRoutingHint = .automobile
        } else {
            coordinates = mapCoordinates(
                trip: trip,
                boardTime: boardTime,
                alightTime: alightTime,
                boardStop: boardStop,
                alightStop: alightStop,
                context: context
            )
            roadRoutingHint = .none
        }

        return RoutePlan.Leg(
            id: "transit-\(trip.id)-\(boardTime.sequence)-\(alightTime.sequence)-\(sequence)",
            mode: route.transportMode,
            instruction: "Take \(routeName ?? route.id) to \(destinationName)",
            transportKind: .transit,
            routeName: routeName,
            headsign: trip.headsign ?? alightTime.headsign,
            routeId: route.id,
            // The shifted ID is an internal service-day key. Keep the GTFS
            // trip identifier at the app boundary so callers and future
            // realtime overlays can match the source archive directly.
            tripId: trip.originalTripID ?? trip.id,
            originStopId: boardStop.id,
            destinationStopId: alightStop.id,
            stopCount: stopCount,
            origin: boardStop.location,
            destination: alightStop.location,
            departureTime: departure,
            arrivalTime: arrival,
            scheduledDepartureTime: departure,
            scheduledArrivalTime: arrival,
            distanceMeters: routeSearchDistanceMeters(from: boardStop.location, to: alightStop.location),
            mapCoordinates: coordinates,
            roadRoutingHint: roadRoutingHint,
            liveStatus: .scheduled
        )
    }

    nonisolated func walkingLeg(
        id: String,
        from origin: LocationPoint,
        to destination: LocationPoint,
        departureSeconds: Int,
        arrivalSeconds: Int,
        serviceStart: Date,
        distanceMeters: Double,
        instruction: String
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: .walking,
            instruction: instruction,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: date(seconds: departureSeconds, from: serviceStart),
            arrivalTime: date(seconds: arrivalSeconds, from: serviceStart),
            distanceMeters: distanceMeters,
            mapCoordinates: [
                RouteMapCoordinate(origin),
                RouteMapCoordinate(destination)
            ],
            roadRoutingHint: .walking,
            liveStatus: .scheduled
        )
    }

    nonisolated func overlay(from legs: [RoutePlan.Leg]) -> RouteMapOverlay? {
        let segments = legs.enumerated().compactMap { index, leg -> RouteMapSegment? in
            let coordinates = leg.mapCoordinates.isEmpty
                ? [RouteMapCoordinate(leg.origin), RouteMapCoordinate(leg.destination)]
                : leg.mapCoordinates
            guard coordinates.count >= 2 else { return nil }
            return RouteMapSegment(
                id: "\(leg.id)-\(index)",
                mode: leg.mode,
                routeName: leg.routeName,
                routeId: leg.routeId,
                coordinates: coordinates
            )
        }
        let overlay = RouteMapOverlay(
            segments: segments,
            transferMarkers: transferMarkers(from: legs)
        )
        return overlay.isEmpty ? nil : overlay
    }

    nonisolated func transferMarkers(from legs: [RoutePlan.Leg]) -> [RouteTransferMarker] {
        var markers: [RouteTransferMarker] = []
        var seen: Set<RouteMapCoordinate> = []

        for (index, leg) in legs.enumerated() where leg.transportKind == .transit {
            guard legs.suffix(from: index + 1).contains(where: { $0.transportKind == .transit }),
                  seen.insert(RouteMapCoordinate(leg.destination)).inserted else {
                continue
            }

            markers.append(RouteTransferMarker(
                id: "transfer-\(leg.id)",
                title: "Transfer",
                coordinate: RouteMapCoordinate(leg.destination)
            ))
        }

        return markers
    }

    nonisolated func copy(
        _ leg: RoutePlan.Leg,
        departureTime: Date? = nil,
        arrivalTime: Date? = nil,
        scheduledDepartureTime: Date? = nil,
        scheduledArrivalTime: Date? = nil,
        realtimeDepartureTime: Date? = nil,
        realtimeArrivalTime: Date? = nil,
        platform: String? = nil,
        delayMinutes: Int? = nil,
        liveStatus: RouteLegLiveStatus? = nil,
        transferWarning: String? = nil,
        distanceMeters: Double? = nil,
        mapCoordinates: [RouteMapCoordinate]? = nil
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: leg.id,
            mode: leg.mode,
            instruction: leg.instruction,
            transportKind: leg.transportKind,
            routeName: leg.routeName,
            headsign: leg.headsign,
            routeId: leg.routeId,
            tripId: leg.tripId,
            originStopId: leg.originStopId,
            destinationStopId: leg.destinationStopId,
            stopCount: leg.stopCount,
            origin: leg.origin,
            destination: leg.destination,
            departureTime: departureTime ?? leg.departureTime,
            arrivalTime: arrivalTime ?? leg.arrivalTime,
            scheduledDepartureTime: scheduledDepartureTime ?? leg.scheduledDepartureTime,
            scheduledArrivalTime: scheduledArrivalTime ?? leg.scheduledArrivalTime,
            realtimeDepartureTime: realtimeDepartureTime ?? leg.realtimeDepartureTime,
            realtimeArrivalTime: realtimeArrivalTime ?? leg.realtimeArrivalTime,
            distanceMeters: distanceMeters ?? leg.distanceMeters,
            mapCoordinates: mapCoordinates ?? leg.mapCoordinates,
            roadRoutingHint: leg.roadRoutingHint,
            platform: platform ?? leg.platform,
            delayMinutes: delayMinutes ?? leg.delayMinutes,
            liveStatus: liveStatus ?? leg.liveStatus,
            transferWarning: transferWarning ?? leg.transferWarning,
            bikeShareDetails: leg.bikeShareDetails
        )
    }

    nonisolated func walkingSeconds(for distanceMeters: Double) -> Int {
        max(0, Int((distanceMeters / walkingSpeedMetersPerSecond).rounded(.up)))
    }

    nonisolated func mapCoordinates(
        trip: GTFSTimetableTripEntry,
        boardTime: GTFSTimetableStopTimeEntry,
        alightTime: GTFSTimetableStopTimeEntry,
        boardStop: GTFSTimetableStopEntry,
        alightStop: GTFSTimetableStopEntry,
        context: RouteSearchContext
    ) -> [RouteMapCoordinate] {
        shapeCoordinates(
            trip: trip,
            boardTime: boardTime,
            alightTime: alightTime,
            boardStop: boardStop,
            alightStop: alightStop,
            context: context
        ) ?? stopCoordinates(
            trip: trip,
            fromSequence: boardTime.sequence,
            toSequence: alightTime.sequence,
            context: context
        )
    }

    nonisolated func shapeCoordinates(
        trip: GTFSTimetableTripEntry,
        boardTime: GTFSTimetableStopTimeEntry,
        alightTime: GTFSTimetableStopTimeEntry,
        boardStop: GTFSTimetableStopEntry,
        alightStop: GTFSTimetableStopEntry,
        context: RouteSearchContext
    ) -> [RouteMapCoordinate]? {
        guard let shapeId = trip.shapeId,
              let shape = context.shapesById[shapeId],
              let startDistance = boardTime.shapeDistanceTraveled,
              let endDistance = alightTime.shapeDistanceTraveled else {
            return nil
        }

        let lower = min(startDistance, endDistance)
        let upper = max(startDistance, endDistance)
        let shapeCoordinates = shape.points
            .filter { point in
                guard let distance = point.distanceTraveled else { return false }
                return (lower ... upper).contains(distance)
            }
            .sorted { $0.sequence < $1.sequence }
            .map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }

        guard !shapeCoordinates.isEmpty else { return nil }

        return [RouteMapCoordinate(boardStop.location)]
            + shapeCoordinates
            + [RouteMapCoordinate(alightStop.location)]
    }

    nonisolated func stopCoordinates(
        trip: GTFSTimetableTripEntry,
        fromSequence: Int,
        toSequence: Int,
        context: RouteSearchContext
    ) -> [RouteMapCoordinate] {
        trip.stopTimes
            .filter { (fromSequence ... toSequence).contains($0.sequence) }
            .compactMap { context.stopsById[$0.stopId]?.location }
            .map { RouteMapCoordinate($0) }
    }

    nonisolated func date(seconds: Int, from serviceStart: Date) -> Date {
        serviceStart.addingTimeInterval(TimeInterval(seconds))
    }
}
