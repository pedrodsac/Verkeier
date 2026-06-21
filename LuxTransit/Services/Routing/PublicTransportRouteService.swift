import CoreLocation
import Foundation
import HeapModule
import MapKit

struct PublicTransportRouteService: RouteService {
    private let engine: PublicTransportRoutingEngine

    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        roadRouteProvider: any RoadRouteProviding = MapKitRoadRouteProvider(),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
            return calendar
        }()
    ) {
        engine = PublicTransportRoutingEngine(
            gtfsService: gtfsService,
            atpClient: atpClient,
            roadRouteProvider: roadRouteProvider,
            now: now,
            calendar: calendar
        )
    }

    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation {
        try await engine.calculateRoute(from: from, to: to)
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        let source = mapItem(for: from)
        let destination = mapItem(for: to)

        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
            ]
        )
    }

    private nonisolated func mapItem(for point: LocationPoint) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: point.latitude, longitude: point.longitude),
            address: nil
        )
        item.name = point.name
        return item
    }

}

protocol RoadRouteProviding: Sendable {
    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]?
}

enum RoadRouteTransport: String, Sendable {
    case automobile
    case walking
}

struct MapKitRoadRouteProvider: RoadRouteProviding {
    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = transport.mapKitTransportType
        request.requestsAlternateRoutes = false

        guard let route = try? await MKDirections(request: request).calculate().routes.first,
              route.polyline.pointCount >= 2 else {
            return nil
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: route.polyline.pointCount)
        )

        return coordinates.map {
            RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private nonisolated func mapItem(for point: LocationPoint) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: point.latitude, longitude: point.longitude),
            address: nil
        )
        item.name = point.name
        return item
    }
}

private extension RoadRouteTransport {
    init?(_ hint: RouteLegRoadRoutingHint) {
        switch hint {
        case .none:
            return nil
        case .automobile:
            self = .automobile
        case .walking:
            self = .walking
        }
    }

    var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .walking: .walking
        }
    }
}

private actor PublicTransportRoutingEngine {
    private let gtfsService: any GTFSService
    private let atpClient: any ATPClient
    private let roadRouteProvider: any RoadRouteProviding
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    private let accessRadiusMeters = 900.0
    private let destinationRadiusMeters = 900.0
    private let transferBufferSeconds = 120
    private let searchHorizonSeconds = 4 * 60 * 60
    private let maximumTransitLegs = 3
    private let walkingSpeedMetersPerSecond = 1.33
    private let evaluatedCandidateLimit = 18
    private let returnedOptionLimit = 18
    private var cachedContext: CachedRouteSearchContext?
    private var roadRouteCoordinateCache: [RoadRouteCacheKey: [RouteMapCoordinate]?] = [:]

    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        roadRouteProvider: any RoadRouteProviding,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.gtfsService = gtfsService
        self.atpClient = atpClient
        self.roadRouteProvider = roadRouteProvider
        self.now = now
        self.calendar = calendar
    }

    func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation {
        guard let timetable = await gtfsService.timetableIndex(), !timetable.trips.isEmpty else {
            throw RoutingError.timetableUnavailable
        }

        let requestNow = now()
        let staticContext = cachedStaticContext(for: timetable, now: requestNow)
        let context = RouteSearchContext(staticContext: staticContext, now: requestNow)
        guard !context.activeTrips.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        let scheduledCandidates = scheduledJourneys(from: from, to: to, context: context)
        guard !scheduledCandidates.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        try Task.checkCancellation()

        let enrichedCandidates = await enrich(
            Array(scheduledCandidates.prefix(evaluatedCandidateLimit)),
            context: context
        )
        let sortedCandidates = enrichedCandidates
            .sorted(by: candidateSort)
            .prefix(returnedOptionLimit)
        var options: [RouteOption] = []
        options.reserveCapacity(sortedCandidates.count)
        for (index, candidate) in sortedCandidates.enumerated() {
            if let option = await routeOption(
                from: candidate,
                index: index,
                origin: from,
                destination: to,
                context: context
            ) {
                options.append(option)
            }
        }

        guard !options.isEmpty else {
            throw RoutingError.noPublicTransportRoute
        }

        let selectedOptionID = options.first?.id
        return RouteCalculation(options: options, selectedOptionID: selectedOptionID)
    }

    private func cachedStaticContext(
        for timetable: GTFSTimetableIndexPayload,
        now: Date
    ) -> CachedRouteSearchContext {
        let key = RouteSearchCacheKey(timetable: timetable, calendar: calendar, now: now)
        if let cachedContext, cachedContext.key == key {
            return cachedContext
        }

        let context = CachedRouteSearchContext(
            key: key,
            timetable: timetable,
            calendar: calendar,
            now: now
        )
        cachedContext = context
        return context
    }

    private func scheduledJourneys(
        from origin: LocationPoint,
        to destination: LocationPoint,
        context: RouteSearchContext
    ) -> [ScheduledJourney] {
        let originStops = nearestStops(
            to: origin,
            in: context,
            radiusMeters: accessRadiusMeters,
            limit: 8
        )
        let destinationStops = destinationStopMatches(
            for: destination,
            in: context,
            radiusMeters: destinationRadiusMeters
        )
        guard !originStops.isEmpty, !destinationStops.isEmpty else { return [] }

        let destinationStopsById = Dictionary(uniqueKeysWithValues: destinationStops.map { ($0.stop.id, $0) })
        var queue = JourneyPriorityQueue()
        for originCandidate in originStops {
            let walkSeconds = walkingSeconds(for: originCandidate.distanceMeters)
            let accessLeg = walkingLeg(
                id: "access-\(originCandidate.stop.id)",
                from: origin,
                to: originCandidate.stop.location,
                departureSeconds: context.currentSeconds,
                arrivalSeconds: context.currentSeconds + walkSeconds,
                serviceStart: context.serviceStart,
                distanceMeters: originCandidate.distanceMeters,
                instruction: "Walk to \(originCandidate.stop.name)"
            )

            queue.push(JourneyState(
                stopId: originCandidate.stop.id,
                readySeconds: context.currentSeconds + walkSeconds,
                legs: originCandidate.distanceMeters > 25 ? [accessLeg] : [],
                transitLegCount: 0,
                visitedStopIds: [originCandidate.stop.id]
            ))
        }

        var candidates: [ScheduledJourney] = []
        var bestArrivalByStopAndLegCount: [String: Int] = [:]
        var expansionCount = 0

        while let state = queue.popMin(), expansionCount < 5_000 {
            if Task.isCancelled { return [] }
            expansionCount += 1

            if let destinationCandidate = destinationStopsById[state.stopId],
               state.transitLegCount > 0 {
                let egressSeconds = walkingSeconds(for: destinationCandidate.distanceMeters)
                let egressLeg = walkingLeg(
                    id: "egress-\(state.stopId)",
                    from: context.stopsById[state.stopId]?.location ?? destinationCandidate.stop.location,
                    to: destination,
                    departureSeconds: state.readySeconds,
                    arrivalSeconds: state.readySeconds + egressSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: destinationCandidate.distanceMeters,
                    instruction: "Walk to \(destination.name ?? destinationCandidate.stop.name)"
                )
                let completeLegs = destinationCandidate.distanceMeters > 25
                    ? state.legs + [egressLeg]
                    : state.legs
                candidates.append(ScheduledJourney(legs: completeLegs))

                if candidates.count >= evaluatedCandidateLimit {
                    continue
                }
            }

            guard state.transitLegCount < maximumTransitLegs else { continue }

            let boardingReadySeconds = state.readySeconds
                + (state.transitLegCount > 0 ? transferBufferSeconds : 0)
            guard boardingReadySeconds <= context.currentSeconds + searchHorizonSeconds else {
                continue
            }

            let references = context.tripReferencesByStopId[state.stopId, default: []]
            for reference in references {
                let trip = context.activeTrips[reference.tripIndex]
                let boardTime = trip.stopTimes[reference.stopTimeIndex]
                guard boardTime.departureSeconds >= boardingReadySeconds else {
                    continue
                }
                guard boardTime.departureSeconds <= context.currentSeconds + searchHorizonSeconds,
                      boardTime.pickupType != "1" else {
                    break
                }

                for downstreamIndex in trip.stopTimes.indices.dropFirst(reference.stopTimeIndex + 1) {
                    let alightTime = trip.stopTimes[downstreamIndex]
                    guard alightTime.dropOffType != "1",
                          alightTime.arrivalSeconds > boardTime.departureSeconds,
                          !state.visitedStopIds.contains(alightTime.stopId),
                          let boardStop = context.stopsById[boardTime.stopId],
                          let alightStop = context.stopsById[alightTime.stopId],
                          let route = context.routesById[trip.routeId] else {
                        continue
                    }

                    let isDestinationStop = destinationStopsById[alightTime.stopId] != nil
                    if !isDestinationStop {
                        let key = "\(alightTime.stopId)|\(state.transitLegCount + 1)"
                        if let bestArrival = bestArrivalByStopAndLegCount[key],
                           bestArrival <= alightTime.arrivalSeconds {
                            continue
                        }
                        bestArrivalByStopAndLegCount[key] = alightTime.arrivalSeconds
                    }

                    let transitLeg = scheduledTransitLeg(
                        sequence: state.legs.count,
                        trip: trip,
                        route: route,
                        boardTime: boardTime,
                        alightTime: alightTime,
                        boardStop: boardStop,
                        alightStop: alightStop,
                        context: context
                    )
                    var visitedStopIds = state.visitedStopIds
                    visitedStopIds.insert(alightTime.stopId)

                    queue.push(JourneyState(
                        stopId: alightTime.stopId,
                        readySeconds: alightTime.arrivalSeconds,
                        legs: state.legs + [transitLeg],
                        transitLegCount: state.transitLegCount + 1,
                        visitedStopIds: visitedStopIds
                    ))
                }
            }

            for transfer in context.transfersByFromStopId[state.stopId, default: []] {
                guard !state.visitedStopIds.contains(transfer.toStopId),
                      let fromStop = context.stopsById[transfer.fromStopId],
                      let toStop = context.stopsById[transfer.toStopId] else {
                    continue
                }
                let distance = distanceMeters(from: fromStop.location, to: toStop.location)
                let seconds = max(
                    transfer.minimumTransferSeconds ?? 0,
                    walkingSeconds(for: distance) + transferBufferSeconds
                )
                let arrivalSeconds = state.readySeconds + seconds
                let key = "\(transfer.toStopId)|\(state.transitLegCount)"
                if let bestArrival = bestArrivalByStopAndLegCount[key],
                   bestArrival <= arrivalSeconds {
                    continue
                }
                bestArrivalByStopAndLegCount[key] = arrivalSeconds

                let transferLeg = walkingLeg(
                    id: "transfer-\(transfer.fromStopId)-\(transfer.toStopId)",
                    from: fromStop.location,
                    to: toStop.location,
                    departureSeconds: state.readySeconds,
                    arrivalSeconds: arrivalSeconds,
                    serviceStart: context.serviceStart,
                    distanceMeters: distance,
                    instruction: "Walk to \(toStop.name)"
                )
                var visitedStopIds = state.visitedStopIds
                visitedStopIds.insert(transfer.toStopId)
                queue.push(JourneyState(
                    stopId: transfer.toStopId,
                    readySeconds: arrivalSeconds,
                    legs: state.legs + [transferLeg],
                    transitLegCount: state.transitLegCount,
                    visitedStopIds: visitedStopIds
                ))
            }
        }

        return deduplicated(
            candidates
                .filter { $0.legs.contains { $0.transportKind == .transit } }
                .sorted { $0.arrivalTime < $1.arrivalTime }
        )
    }

    private func enrich(
        _ candidates: [ScheduledJourney],
        context: RouteSearchContext
    ) async -> [RouteCandidate] {
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

    private func departureBoardsByStopId(stopIds: Set<String>) async -> [String: [Departure]] {
        await withTaskGroup(of: (String, [Departure]).self) { group in
            for stopId in stopIds {
                group.addTask {
                    let platformIds = await self.gtfsService.stop(id: stopId)?.platformIds ?? [stopId]
                    let departures = (try? await self.atpClient.departureBoards(stopIds: platformIds)) ?? []
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

    private func deduplicated(_ candidates: [ScheduledJourney]) -> [ScheduledJourney] {
        var seen: Set<String> = []
        var unique: [ScheduledJourney] = []

        for candidate in candidates {
            let signature = candidate.signature
            if seen.insert(signature).inserted {
                unique.append(candidate)
            }
        }

        return unique
    }

    private func routeOption(
        from candidate: RouteCandidate,
        index: Int,
        origin: LocationPoint,
        destination: LocationPoint,
        context: RouteSearchContext
    ) async -> RouteOption? {
        let legs = legsWithTransferWarnings(candidate.legs)
        guard legs.contains(where: { $0.transportKind == .transit }) else {
            return nil
        }
        let overlayLegs = await legsWithRoadRoutedSegments(legs)

        let optionID = "gtfs-option-\(origin.id)-\(destination.id)-\(Int(context.now.timeIntervalSince1970))-\(index)"
        let plan = RoutePlan(
            id: optionID,
            origin: origin,
            destination: destination,
            expectedTravelTime: legs.compactMap(\.arrivalTime).last?.timeIntervalSince(context.now),
            distanceMeters: legs.compactMap(\.distanceMeters).reduce(0, +),
            legs: legs,
            dataSource: .gtfs
        )
        return RouteOption(id: optionID, plan: plan, mapOverlay: overlay(from: overlayLegs))
    }

    private func legsWithRoadRoutedSegments(_ legs: [RoutePlan.Leg]) async -> [RoutePlan.Leg] {
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

    private func roadCoordinates(
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

    private func roadCoordinates(
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

    private func acceptableRoadCoordinates(
        _ coordinates: [RouteMapCoordinate],
        from origin: RouteMapCoordinate,
        to destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) -> [RouteMapCoordinate]? {
        guard coordinates.count >= 2 else { return nil }

        let directDistance = distanceMeters(
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

    private func polylineDistanceMeters(_ coordinates: [RouteMapCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + distanceMeters(
                from: LocationPoint(latitude: pair.0.latitude, longitude: pair.0.longitude),
                to: LocationPoint(latitude: pair.1.latitude, longitude: pair.1.longitude)
            )
        }
    }

    private func distanceFromRouteCorridorMeters(
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

    private func projectedFraction(
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

    private func matchedDeparture(for leg: RoutePlan.Leg, in departures: [Departure]) -> Departure? {
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

    private func routeMatches(departure: Departure, leg: RoutePlan.Leg) -> Bool {
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

    private func liveLeg(_ leg: RoutePlan.Leg, departure: Departure) -> RoutePlan.Leg {
        let delay = departure.delayMinutes
        let realtimeDeparture = departure.realtimeDeparture
        let realtimeArrival = delay.map { minutes in
            (leg.scheduledArrivalTime ?? leg.arrivalTime)?.addingTimeInterval(Double(minutes * 60))
        } ?? nil
        let liveStatus: RouteLegLiveStatus
        if departure.isCancelled {
            liveStatus = .cancelled
        } else if let delay, delay > 0 {
            liveStatus = .delayed
        } else if realtimeDeparture != nil {
            liveStatus = .live
        } else {
            liveStatus = .unknown
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

    private func legsWithTransferWarnings(_ legs: [RoutePlan.Leg]) -> [RoutePlan.Leg] {
        var result = legs

        for index in result.indices.dropLast() {
            let current = result[index]
            let next = result[index + 1]
            guard current.transportKind == .transit,
                  next.transportKind == .transit,
                  let arrival = current.realtimeArrivalTime ?? current.scheduledArrivalTime ?? current.arrivalTime,
                  let nextDeparture = next.realtimeDepartureTime ?? next.scheduledDepartureTime ?? next.departureTime,
                  arrival.addingTimeInterval(Double(transferBufferSeconds)) > nextDeparture else {
                continue
            }

            result[index] = copy(current, transferWarning: "Connection may be missed")
        }

        return result
    }

    private func brokenConnectionPenalty(for legs: [RoutePlan.Leg]) -> Int {
        var penalty = 0
        for index in legs.indices.dropLast() {
            let current = legs[index]
            let next = legs[index + 1]
            guard current.transportKind == .transit,
                  next.transportKind == .transit,
                  let arrival = current.realtimeArrivalTime ?? current.scheduledArrivalTime ?? current.arrivalTime,
                  let nextDeparture = next.realtimeDepartureTime ?? next.scheduledDepartureTime ?? next.departureTime,
                  arrival.addingTimeInterval(Double(transferBufferSeconds)) > nextDeparture else {
                continue
            }
            penalty += 50_000
        }
        return penalty
    }

    private func candidateSort(_ lhs: RouteCandidate, _ rhs: RouteCandidate) -> Bool {
        let lhsArrival = lhs.legs.compactMap(\.arrivalTime).last ?? .distantFuture
        let rhsArrival = rhs.legs.compactMap(\.arrivalTime).last ?? .distantFuture
        return lhsArrival.addingTimeInterval(TimeInterval(lhs.penalty))
            < rhsArrival.addingTimeInterval(TimeInterval(rhs.penalty))
    }

    private func nearestStops(
        to point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double,
        limit: Int
    ) -> [StopCandidate] {
        context.stopsById.values
            .compactMap { stop -> StopCandidate? in
                let distance = distanceMeters(from: point, to: stop.location)
                guard distance <= radiusMeters else { return nil }
                return StopCandidate(stop: stop, distanceMeters: distance)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map(\.self)
    }

    private func destinationStopMatches(
        for point: LocationPoint,
        in context: RouteSearchContext,
        radiusMeters: Double
    ) -> [StopCandidate] {
        let normalizedName = point.name?.normalizedForSearch
        let matches = context.stopsById.values.compactMap { stop -> StopCandidate? in
            let distance = distanceMeters(from: point, to: stop.location)
            let idMatches = stop.id == point.id
            let nameMatches = normalizedName?.isEmpty == false
                && stop.name.normalizedForSearch == normalizedName
                && distance <= 2_500
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

    private func scheduledTransitLeg(
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
        let destinationName = alightTime.headsign ?? trip.headsign ?? alightStop.name
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
            distanceMeters: distanceMeters(from: boardStop.location, to: alightStop.location),
            mapCoordinates: coordinates,
            roadRoutingHint: roadRoutingHint,
            liveStatus: .scheduled
        )
    }

    private func walkingLeg(
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

    private func overlay(from legs: [RoutePlan.Leg]) -> RouteMapOverlay? {
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

    private func transferMarkers(from legs: [RoutePlan.Leg]) -> [RouteTransferMarker] {
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

    private func copy(
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
            transferWarning: transferWarning ?? leg.transferWarning
        )
    }

    private func walkingSeconds(for distanceMeters: Double) -> Int {
        max(0, Int((distanceMeters / walkingSpeedMetersPerSecond).rounded(.up)))
    }

    private func mapCoordinates(
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

    private func shapeCoordinates(
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
                return (lower...upper).contains(distance)
            }
            .sorted { $0.sequence < $1.sequence }
            .map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }

        guard !shapeCoordinates.isEmpty else { return nil }

        return [RouteMapCoordinate(boardStop.location)]
            + shapeCoordinates
            + [RouteMapCoordinate(alightStop.location)]
    }

    private func stopCoordinates(
        trip: GTFSTimetableTripEntry,
        fromSequence: Int,
        toSequence: Int,
        context: RouteSearchContext
    ) -> [RouteMapCoordinate] {
        trip.stopTimes
            .filter { (fromSequence...toSequence).contains($0.sequence) }
            .compactMap { context.stopsById[$0.stopId]?.location }
            .map { RouteMapCoordinate($0) }
    }

    private func date(seconds: Int, from serviceStart: Date) -> Date {
        serviceStart.addingTimeInterval(TimeInterval(seconds))
    }
}

private nonisolated struct RouteSearchContext {
    private let staticContext: CachedRouteSearchContext
    let now: Date
    let currentSeconds: Int

    var serviceStart: Date { staticContext.serviceStart }
    var stopsById: [String: GTFSTimetableStopEntry] { staticContext.stopsById }
    var routesById: [String: GTFSTimetableRouteEntry] { staticContext.routesById }
    var shapesById: [String: GTFSTimetableShapeEntry] { staticContext.shapesById }
    var activeTrips: [GTFSTimetableTripEntry] { staticContext.activeTrips }
    var tripReferencesByStopId: [String: [TripStopReference]] { staticContext.tripReferencesByStopId }
    var transfersByFromStopId: [String: [GTFSTimetableTransferEntry]] { staticContext.transfersByFromStopId }

    init(staticContext: CachedRouteSearchContext, now: Date) {
        self.staticContext = staticContext
        self.now = now
        currentSeconds = max(0, Int(now.timeIntervalSince(staticContext.serviceStart)))
    }
}

private nonisolated struct CachedRouteSearchContext {
    let key: RouteSearchCacheKey
    let serviceStart: Date
    let stopsById: [String: GTFSTimetableStopEntry]
    let routesById: [String: GTFSTimetableRouteEntry]
    let shapesById: [String: GTFSTimetableShapeEntry]
    let activeTrips: [GTFSTimetableTripEntry]
    let tripReferencesByStopId: [String: [TripStopReference]]
    let transfersByFromStopId: [String: [GTFSTimetableTransferEntry]]

    init(
        key: RouteSearchCacheKey,
        timetable: GTFSTimetableIndexPayload,
        calendar: Calendar,
        now: Date
    ) {
        self.key = key
        serviceStart = calendar.startOfDay(for: now)
        stopsById = Dictionary(uniqueKeysWithValues: timetable.stops.map { ($0.id, $0) })
        routesById = Dictionary(uniqueKeysWithValues: timetable.routes.map { ($0.id, $0) })
        shapesById = Dictionary(uniqueKeysWithValues: timetable.shapes.map { ($0.id, $0) })

        let activeServiceIds = Self.activeServiceIds(
            in: timetable.services,
            on: now,
            calendar: calendar
        )
        let activeTripsValue = timetable.trips.filter { activeServiceIds.contains($0.serviceId) }

        var references: [String: [TripStopReference]] = [:]
        for tripIndex in activeTripsValue.indices {
            let trip = activeTripsValue[tripIndex]
            for stopTimeIndex in trip.stopTimes.indices.dropLast() {
                let stopTime = trip.stopTimes[stopTimeIndex]
                references[stopTime.stopId, default: []].append(
                    TripStopReference(tripIndex: tripIndex, stopTimeIndex: stopTimeIndex)
                )
            }
        }
        let sortedReferences = references.mapValues {
            $0.sorted {
                activeTripsValue[$0.tripIndex].stopTimes[$0.stopTimeIndex].departureSeconds
                    < activeTripsValue[$1.tripIndex].stopTimes[$1.stopTimeIndex].departureSeconds
            }
        }

        activeTrips = activeTripsValue
        tripReferencesByStopId = sortedReferences
        transfersByFromStopId = Dictionary(grouping: timetable.transfers, by: \.fromStopId)
    }

    private static func activeServiceIds(
        in services: [GTFSTimetableServiceEntry],
        on date: Date,
        calendar: Calendar
    ) -> Set<String> {
        let dateString = RouteSearchCacheKey.gtfsDateString(from: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: date)

        return Set(services.compactMap { service in
            if service.removedDates.contains(dateString) {
                return nil
            }
            if service.addedDates.contains(dateString) {
                return service.id
            }
            guard service.weekdays.contains(weekday) else {
                return nil
            }
            if let startDate = service.startDate, startDate > dateString {
                return nil
            }
            if let endDate = service.endDate, endDate < dateString {
                return nil
            }
            return service.id
        })
    }
}

private nonisolated struct RouteSearchCacheKey: Equatable {
    let source: String
    let date: String
    let stopCount: Int
    let routeCount: Int
    let serviceCount: Int
    let tripCount: Int
    let transferCount: Int
    let shapeCount: Int

    init(timetable: GTFSTimetableIndexPayload, calendar: Calendar, now: Date) {
        source = timetable.source
        date = Self.gtfsDateString(from: now, calendar: calendar)
        stopCount = timetable.stops.count
        routeCount = timetable.routes.count
        serviceCount = timetable.services.count
        tripCount = timetable.trips.count
        transferCount = timetable.transfers.count
        shapeCount = timetable.shapes.count
    }

    static func gtfsDateString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private nonisolated struct TripStopReference {
    let tripIndex: Int
    let stopTimeIndex: Int
}

private nonisolated struct StopCandidate {
    let stop: GTFSTimetableStopEntry
    let distanceMeters: Double
}

private nonisolated struct JourneyState: Comparable {
    let stopId: String
    let readySeconds: Int
    let legs: [RoutePlan.Leg]
    let transitLegCount: Int
    let visitedStopIds: Set<String>

    static func < (lhs: JourneyState, rhs: JourneyState) -> Bool {
        lhs.readySeconds < rhs.readySeconds
    }
}

private nonisolated struct ScheduledJourney {
    let legs: [RoutePlan.Leg]

    var arrivalTime: Date {
        legs.compactMap(\.arrivalTime).last ?? .distantFuture
    }

    var signature: String {
        legs.map { leg in
            [
                leg.transportKind.rawValue,
                leg.routeId ?? leg.routeName ?? leg.id,
                leg.originStopId ?? leg.origin.id,
                leg.destinationStopId ?? leg.destination.id,
                String(Int((leg.scheduledDepartureTime ?? leg.departureTime)?.timeIntervalSince1970 ?? 0)),
                String(Int((leg.scheduledArrivalTime ?? leg.arrivalTime)?.timeIntervalSince1970 ?? 0))
            ].joined(separator: "|")
        }.joined(separator: "->")
    }
}

private nonisolated struct RouteCandidate {
    let legs: [RoutePlan.Leg]
    let penalty: Int
}

private nonisolated struct RoadRouteCacheKey: Hashable {
    let transport: RoadRouteTransport
    let originLatitude: Double
    let originLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double

    init(
        origin: RouteMapCoordinate,
        destination: RouteMapCoordinate,
        transport: RoadRouteTransport
    ) {
        self.transport = transport
        originLatitude = origin.latitude
        originLongitude = origin.longitude
        destinationLatitude = destination.latitude
        destinationLongitude = destination.longitude
    }
}

private nonisolated struct JourneyPriorityQueue {
    private var storage = Heap<QueuedJourneyState>()
    private var nextSequence = 0

    var isEmpty: Bool {
        storage.isEmpty
    }

    mutating func push(_ element: JourneyState) {
        storage.insert(QueuedJourneyState(state: element, sequence: nextSequence))
        nextSequence += 1
    }

    mutating func popMin() -> JourneyState? {
        storage.popMin()?.state
    }
}

private nonisolated struct QueuedJourneyState: Comparable {
    let state: JourneyState
    let sequence: Int

    static func < (lhs: QueuedJourneyState, rhs: QueuedJourneyState) -> Bool {
        if lhs.state.readySeconds != rhs.state.readySeconds {
            return lhs.state.readySeconds < rhs.state.readySeconds
        }
        return lhs.sequence < rhs.sequence
    }
}

private nonisolated func distanceMeters(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
    let earthRadius = 6_371_000.0
    let lat1 = lhs.latitude * .pi / 180
    let lat2 = rhs.latitude * .pi / 180
    let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
    let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180

    let a = sin(deltaLat / 2) * sin(deltaLat / 2)
        + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
}
