import CoreLocation
import Foundation
import HeapModule
import MapKit

extension PublicTransportRoutingEngine {
    func justInTimeLeadingWalk(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        guard let firstTransitIndex = legs.firstIndex(where: { $0.transportKind == .transit }),
              firstTransitIndex > 0,
              let board = legs[firstTransitIndex].scheduledDepartureTime
              ?? legs[firstTransitIndex].departureTime else {
            return legs
        }

        var result = legs
        var anchor = board
        for index in stride(from: firstTransitIndex - 1, through: 0, by: -1) {
            let leg = result[index]
            guard leg.transportKind == .walking,
                  let departure = leg.departureTime,
                  let arrival = leg.arrivalTime else {
                break
            }
            let duration = arrival.timeIntervalSince(departure)
            let shiftedDeparture = anchor.addingTimeInterval(-duration)
            result[index] = copy(leg, departureTime: shiftedDeparture, arrivalTime: anchor)
            anchor = shiftedDeparture
        }
        return result
    }

    func enrich(
        _ candidates: [ScheduledJourney],
        context _: RouteSearchContext
    ) async -> [RouteCandidate] {
        // Offline mode plans purely on the static schedule — no ATP fetch, and no
        // no-realtime penalty (which would otherwise flag every leg as unverified).
        guard !offlineMode else {
            return candidates.map {
                RouteCandidate(legs: $0.legs, penalty: brokenConnectionPenalty(for: $0.legs))
            }
        }

        let stopIds = Set(candidates.flatMap { journey in
            journey.legs.compactMap { leg in
                leg.transportKind == .transit ? leg.originStopId : nil
            }
        })

        let boardsByStopId = await departureBoardsByStopId(stopIds: stopIds)
        var enriched: [RouteCandidate] = []
        enriched.reserveCapacity(candidates.count)

        for candidate in candidates {
            var legs: [RoutePlan.Leg] = []
            legs.reserveCapacity(candidate.legs.count)
            var penalty = 0

            for leg in candidate.legs {
                guard leg.transportKind == .transit,
                      let originStopId = leg.originStopId else {
                    legs.append(leg)
                    continue
                }

                let departures = boardsByStopId[originStopId, default: []]
                if let matchedDeparture = matchedDeparture(for: leg, in: departures) {
                    let enrichedLeg = liveLeg(leg, departure: matchedDeparture)
                    penalty += matchedDeparture.isCancelled ? 100_000 : 0
                    penalty += matchedDeparture.realtimeDeparture == nil ? 60 : 0
                    legs.append(enrichedLeg)
                } else {
                    penalty += 60
                    legs.append(leg)
                }
            }

            penalty += brokenConnectionPenalty(for: legs)
            enriched.append(RouteCandidate(legs: legs, penalty: penalty))
        }

        return enriched
    }

    func departureBoardsByStopId(stopIds: Set<String>) async -> [String: [Departure]] {
        await withTaskGroup(of: (String, [Departure]).self) { group in
            for stopId in stopIds {
                group.addTask {
                    let platformIds = await self.gtfsService.stop(id: stopId)?.platformIds ?? [stopId]
                    let departures = await (try? self.atpClient.departureBoards(stopIds: platformIds)) ?? []
                    return (stopId, departures)
                }
            }

            var boardsByStopId: [String: [Departure]] = [:]
            for await (stopId, departures) in group {
                boardsByStopId[stopId] = departures
            }
            return boardsByStopId
        }
    }

    /// Collapses journeys that ride the **same ordered sequence of vehicle trips** into
    /// one. Two itineraries on the identical buses that just change at a different shared
    /// stop (or board the same trip from a different nearby access stop) are one journey
    /// to the rider, not five — so they keyed on stop IDs before and showed up repeatedly.
    /// Keeps the most comfortable representative per trip sequence.
    func routeOption(
        from candidate: RouteCandidate,
        origin: LocationPoint,
        destination: LocationPoint,
        context _: RouteSearchContext
    ) async -> RouteOption? {
        let legs = legsWithTransferWarnings(candidate.legs)
        guard legs.contains(where: {
            $0.transportKind == .transit || $0.transportKind == .bikeShare
        }) else {
            return nil
        }
        let overlayLegs = await legsWithRoadRoutedSegments(legs)

        let optionID = "gtfs-option-\(origin.id)-\(destination.id)-\(optionSignature(for: legs))"
        let plan = RoutePlan(
            id: optionID,
            origin: origin,
            destination: destination,
            expectedTravelTime: travelTime(for: legs),
            distanceMeters: legs.compactMap(\.distanceMeters).reduce(0, +),
            legs: legs,
            dataSource: .gtfs
        )
        return RouteOption(id: optionID, plan: plan, mapOverlay: overlay(from: overlayLegs))
    }

    func legsWithRoadRoutedSegments(_ legs: [RoutePlan.Leg]) async -> [RoutePlan.Leg] {
        var result = legs
        for index in result.indices {
            guard let transport = RoadRouteTransport(result[index].roadRoutingHint) else {
                continue
            }

            let coordinates = result[index].mapCoordinates.isEmpty
                ? [RouteMapCoordinate(result[index].origin), RouteMapCoordinate(result[index].destination)]
                : result[index].mapCoordinates
            guard let roadCoordinates = await roadCoordinates(
                connecting: coordinates,
                transport: transport
            ) else {
                continue
            }
            result[index] = copy(result[index], mapCoordinates: roadCoordinates)
        }
        return result
    }

    func roadCoordinates(
        connecting coordinates: [RouteMapCoordinate],
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        guard coordinates.count >= 2 else { return nil }

        var routedCoordinates: [RouteMapCoordinate] = []
        for pair in zip(coordinates, coordinates.dropFirst()) {
            guard !Task.isCancelled else { return nil }

            guard let segmentCoordinates = await roadCoordinates(
                from: pair.0,
                to: pair.1,
                transport: transport
            ),
                segmentCoordinates.count >= 2 else {
                return nil
            }

            if routedCoordinates.isEmpty {
                routedCoordinates.append(contentsOf: segmentCoordinates)
            } else {
                routedCoordinates.append(contentsOf: segmentCoordinates.dropFirst())
            }
        }

        return routedCoordinates.count >= 2 ? routedCoordinates : nil
    }

    func roadCoordinates(
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        let key = RoadRouteCacheKey(
            origin: origin,
            destination: destination,
            transport: transport
        )
        if let cachedCoordinates = roadRouteCoordinateCache[key] {
            return cachedCoordinates
        }

        let coordinates = await roadRouteProvider.roadRouteCoordinates(
            from: LocationPoint(
                latitude: origin.latitude,
                longitude: origin.longitude
            ),
            to: LocationPoint(
                latitude: destination.latitude,
                longitude: destination.longitude
            ),
            transport: transport
        )
        let acceptedCoordinates = coordinates.flatMap {
            acceptableRoadCoordinates($0, from: origin, to: destination, transport: transport)
        }
        roadRouteCoordinateCache[key] = acceptedCoordinates
        return acceptedCoordinates
    }

    func acceptableRoadCoordinates(
        _ coordinates: [RouteMapCoordinate],
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) -> [RouteMapCoordinate]? {
        guard coordinates.count >= 2 else { return nil }

        let directDistance = routeSearchDistanceMeters(
            from: LocationPoint(latitude: origin.latitude, longitude: origin.longitude),
            to: LocationPoint(latitude: destination.latitude, longitude: destination.longitude)
        )
        guard directDistance > 0 else { return coordinates }

        let routedDistance = polylineDistanceMeters(coordinates)
        let maximumDistanceRatio = transport == .automobile ? 2.2 : 2.8
        let maximumExtraDistance = transport == .automobile ? 600.0 : 900.0
        let allowedDistance = max(
            directDistance * maximumDistanceRatio,
            directDistance + maximumExtraDistance
        )
        guard routedDistance <= allowedDistance else { return nil }

        let maximumDetourDistance = max(directDistance * 1.25, 350.0)
        guard coordinates.allSatisfy({
            distanceFromRouteCorridorMeters(point: $0, origin: origin, destination: destination)
                <= maximumDetourDistance
        }) else {
            return nil
        }

        return coordinates
    }

    func polylineDistanceMeters(_ coordinates: [RouteMapCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + routeSearchDistanceMeters(
                from: LocationPoint(latitude: pair.0.latitude, longitude: pair.0.longitude),
                to: LocationPoint(latitude: pair.1.latitude, longitude: pair.1.longitude)
            )
        }
    }

    func distanceFromRouteCorridorMeters(
        point: RouteMapCoordinate,
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate
    ) -> Double {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let routeDistance = originLocation.distance(from: destinationLocation)
        guard routeDistance > 0 else {
            return pointLocation.distance(from: originLocation)
        }

        let t = max(0, min(1, projectedFraction(
            point: point,
            origin: origin,
            destination: destination
        )))
        let interpolated = CLLocation(
            latitude: origin.latitude + (destination.latitude - origin.latitude) * t,
            longitude: origin.longitude + (destination.longitude - origin.longitude) * t
        )
        return pointLocation.distance(from: interpolated)
    }

    func projectedFraction(
        point: RouteMapCoordinate,
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate
    ) -> Double {
        let originLatitude = origin.latitude * .pi / 180
        let longitudeScale = cos(originLatitude)
        let routeX = (destination.longitude - origin.longitude) * longitudeScale
        let routeY = destination.latitude - origin.latitude
        let pointX = (point.longitude - origin.longitude) * longitudeScale
        let pointY = point.latitude - origin.latitude
        let denominator = routeX * routeX + routeY * routeY
        guard denominator > 0 else { return 0 }
        return (pointX * routeX + pointY * routeY) / denominator
    }

    func matchedDeparture(for leg: RoutePlan.Leg, in departures: [Departure]) -> Departure? {
        let scheduledDeparture = leg.scheduledDepartureTime ?? leg.departureTime
        return departures
            .filter { departure in
                guard routeMatches(departure: departure, leg: leg) else { return false }
                guard let scheduledDeparture,
                      let boardDeparture = departure.scheduledDeparture else {
                    return true
                }
                return abs(boardDeparture.timeIntervalSince(scheduledDeparture)) <= 20 * 60
            }
            .min { lhs, rhs in
                guard let scheduledDeparture else { return lhs.lineName < rhs.lineName }
                let lhsDelta = abs((lhs.scheduledDeparture ?? .distantFuture).timeIntervalSince(scheduledDeparture))
                let rhsDelta = abs((rhs.scheduledDeparture ?? .distantFuture).timeIntervalSince(scheduledDeparture))
                return lhsDelta < rhsDelta
            }
    }

    func routeMatches(departure: Departure, leg: RoutePlan.Leg) -> Bool {
        if let routeId = leg.routeId,
           departure.routeId?.caseInsensitiveCompare(routeId) == .orderedSame {
            return true
        }

        if let routeName = leg.routeName,
           departure.lineName.caseInsensitiveCompare(routeName) == .orderedSame {
            return true
        }

        return false
    }

    func liveLeg(_ leg: RoutePlan.Leg, departure: Departure) -> RoutePlan.Leg {
        let delay = departure.delayMinutes
        let realtimeDeparture = departure.realtimeDeparture
        let realtimeArrival = delay.map { minutes in
            (leg.scheduledArrivalTime ?? leg.arrivalTime)?.addingTimeInterval(Double(minutes * 60))
        } ?? nil
        let liveStatus: RouteLegLiveStatus = if departure.isCancelled {
            .cancelled
        } else if let delay, delay > 0 {
            .delayed
        } else if realtimeDeparture != nil {
            .live
        } else {
            .unknown
        }

        return copy(
            leg,
            departureTime: realtimeDeparture ?? leg.departureTime,
            arrivalTime: realtimeArrival ?? leg.arrivalTime,
            realtimeDepartureTime: realtimeDeparture,
            realtimeArrivalTime: realtimeArrival,
            platform: departure.platform,
            delayMinutes: delay,
            liveStatus: liveStatus
        )
    }

    func legsWithTransferWarnings(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result = legs

        for index in result.indices.dropLast() {
            let current = result[index]
            let next = result[index + 1]
            guard current.transportKind == .transit,
                  next.transportKind == .transit,
                  let arrival = current.realtimeArrivalTime ?? current.scheduledArrivalTime ?? current.arrivalTime,
                  let nextDeparture = next.realtimeDepartureTime ?? next.scheduledDepartureTime ?? next.departureTime
            else {
                continue
            }

            let slack = nextDeparture.timeIntervalSince(arrival)
            guard slack < Double(tightTransferThresholdSeconds) else { continue }

            let warning = if slack < Double(transferBufferSeconds) {
                "Connection may be missed"
            } else {
                "Tight connection — \(max(1, Int(slack / 60))) min to change"
            }
            result[index] = copy(current, transferWarning: warning)
        }

        return result
    }
}
