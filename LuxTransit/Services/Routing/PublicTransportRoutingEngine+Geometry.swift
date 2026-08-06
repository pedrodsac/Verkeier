import CoreLocation
import Foundation
import HeapModule
import MapKit

extension PublicTransportRoutingEngine {
    func destinationStopMatches(
        for point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double
    ) -> [StopCandidate] {
        let normalizedName = point.name?.normalizedForSearch
        let matches = context.stopsById.values.compactMap { stop -> StopCandidate? in
            let distance = routeSearchDistanceMeters(from: point, to: stop.location)
            let idMatches = stop.id == point.id
            let nameMatches = normalizedName?.isEmpty == false
                && stop.name.normalizedForSearch == normalizedName
                && distance <= 2500
            let distanceMatches = distance <= radiusMeters

            guard idMatches || nameMatches || distanceMatches else { return nil }
            return StopCandidate(stop: stop, distanceMeters: idMatches ? 0 : distance)
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

    func scheduledTransitLeg(
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
            tripId: trip.id,
            originStopId: boardStop.id,
            destinationStopId: alightStop.id,
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

    func walkingLeg(
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

    func overlay(from legs: [RoutePlan.Leg]) -> RouteMapOverlay? {
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

    func transferMarkers(from legs: [RoutePlan.Leg]) -> [RouteTransferMarker] {
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

    func copy(
        _ leg: RoutePlan.Leg,
        departureTime: Date? = nil,
        arrivalTime: Date? = nil,
        realtimeDepartureTime: Date? = nil,
        realtimeArrivalTime: Date? = nil,
        platform: String? = nil,
        delayMinutes: Int? = nil,
            liveStatus: RouteLegLiveStatus? = nil,
            transferWarning: String? = nil,
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
            origin: leg.origin,
            destination: leg.destination,
            departureTime: departureTime ?? leg.departureTime,
            arrivalTime: arrivalTime ?? leg.arrivalTime,
            scheduledDepartureTime: leg.scheduledDepartureTime,
            scheduledArrivalTime: leg.scheduledArrivalTime,
            realtimeDepartureTime: realtimeDepartureTime ?? leg.realtimeDepartureTime,
            realtimeArrivalTime: realtimeArrivalTime ?? leg.realtimeArrivalTime,
            distanceMeters: leg.distanceMeters,
            mapCoordinates: mapCoordinates ?? leg.mapCoordinates,
            roadRoutingHint: leg.roadRoutingHint,
            platform: platform ?? leg.platform,
            delayMinutes: delayMinutes ?? leg.delayMinutes,
            liveStatus: liveStatus ?? leg.liveStatus,
            transferWarning: transferWarning ?? leg.transferWarning,
            bikeShareDetails: leg.bikeShareDetails
        )
    }

    func walkingSeconds(for distanceMeters: Double) -> Int {
        max(0, Int((distanceMeters / walkingSpeedMetersPerSecond).rounded(.up)))
    }

    func mapCoordinates(
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

    func shapeCoordinates(
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

    func stopCoordinates(
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

    func date(seconds: Int, from serviceStart: Date) -> Date {
        serviceStart.addingTimeInterval(TimeInterval(seconds))
    }
}
