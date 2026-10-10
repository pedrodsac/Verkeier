import Foundation

/// One direct vel’OH! alternative, kept outside the transit result budget.
/// Ride geometry is a pedestrian-path approximation, as documented in DATA_SOURCES.
nonisolated struct BikeShareRoutePlanner: Sendable {
    let stations: any BikeShareService
    let roads: any RoadRouteProviding

    func option(from origin: LocationPoint, to destination: LocationPoint,
                time: RoutePlanningTime, now: Date = .now) async -> RouteOption? {
        await stations.refreshAvailability()
        guard !Task.isCancelled else { return nil }
        let all = await stations.bikeShareStations(near: origin)
        let pickups = candidates(in: all, near: origin)
        let returns = candidates(in: all, near: destination)
        guard !pickups.isEmpty, !returns.isEmpty else { return nil }

        let access = await paths(pickups.map { (origin, $0.location) })
        guard access.contains(where: { $0.map { $0.distanceMeters <= 1_000 } == true }) else { return nil }
        let egress = await paths(returns.map { ($0.location, destination) })
        let pairs = pickups.indices.flatMap { pickup in
            returns.indices.compactMap { dropoff -> (Int, Int)? in
                guard pickups[pickup].id != returns[dropoff].id,
                      let start = access[pickup], start.distanceMeters <= 1_000,
                      let end = egress[dropoff], end.distanceMeters <= 1_000 else { return nil }
                return (pickup, dropoff)
            }
        }
        let rides = await paths(pairs.map { (pickups[$0.0].location, returns[$0.1].location) })
        var best: RouteOption?
        // Completion order never determines the winner or changes tie breaking.
        for (index, pair) in pairs.enumerated() {
            guard !Task.isCancelled else { return nil }
            guard let ride = rides[index], ride.distanceMeters > 0, ride.distanceMeters <= 12_000,
                  let start = access[pair.0], let end = egress[pair.1] else { continue }
            let candidate = makeOption(origin: origin, destination: destination,
                pickup: pickups[pair.0], dropoff: returns[pair.1], access: start,
                ride: ride, egress: end, time: time, now: now)
            if let previous = best {
                if isBetter(candidate, than: previous) { best = candidate }
            } else { best = candidate }
        }
        return Task.isCancelled ? nil : best
    }

    private func paths(_ pairs: [(LocationPoint, LocationPoint)]) async -> [RoadRoute?] {
        guard !Task.isCancelled, !pairs.isEmpty else { return Array(repeating: nil, count: pairs.count) }
        return await withTaskGroup(of: (Int, RoadRoute?).self) { group in
            var next = 0
            var results = Array<RoadRoute?>(repeating: nil, count: pairs.count)
            func add(_ index: Int) {
                group.addTask { (index, await path(from: pairs[index].0, to: pairs[index].1)) }
            }
            for _ in 0..<min(2, pairs.count) { add(next); next += 1 }
            while let (index, route) = await group.next() {
                results[index] = route
                if next < pairs.count, !Task.isCancelled { add(next); next += 1 }
            }
            return results
        }
    }

    private func isBetter(_ candidate: RouteOption, than other: RouteOption) -> Bool {
        if candidate.hasBikeAvailabilityWarning != other.hasBikeAvailabilityWarning {
            return !candidate.hasBikeAvailabilityWarning
        }
        return (candidate.plan.expectedTravelTime ?? .infinity) < (other.plan.expectedTravelTime ?? .infinity)
    }

    private func candidates(in stations: [BikeShareStation], near point: LocationPoint) -> [BikeShareStation] {
        Array(stations.filter {
            $0.isOpen != false && routeSearchDistanceMeters(from: $0.location, to: point) <= 700
        }.sorted {
            let left = routeSearchDistanceMeters(from: $0.location, to: point)
            let right = routeSearchDistanceMeters(from: $1.location, to: point)
            return left == right ? $0.id < $1.id : left < right
        }.prefix(2))
    }

    private func path(from: LocationPoint, to: LocationPoint) async -> RoadRoute? {
        if routeSearchDistanceMeters(from: from, to: to) < 1 {
            return RoadRoute(coordinates: [RouteMapCoordinate(from), RouteMapCoordinate(to)],
                             distanceMeters: 0, expectedTravelTime: 0)
        }
        guard let path = await roads.roadRoute(from: from, to: to, transport: .walking),
              path.walkingEvidence == .routedPedestrian,
              path.coordinates.count >= 2, path.distanceMeters.isFinite, path.distanceMeters >= 0,
              let duration = path.expectedTravelTime, duration.isFinite, duration >= 0 else { return nil }
        return path
    }

    private func makeOption(origin: LocationPoint, destination: LocationPoint,
        pickup: BikeShareStation, dropoff: BikeShareStation,
        access: RoadRoute, ride: RoadRoute, egress: RoadRoute,
        time: RoutePlanningTime, now: Date) -> RouteOption {
        let accessSeconds = access.expectedTravelTime ?? 0
        let egressSeconds = egress.expectedTravelTime ?? 0
        let rideSeconds = ceil(ride.distanceMeters / (15_000 / 3_600)) + 120
        let duration = accessSeconds + rideSeconds + egressSeconds
        let start: Date = switch time {
        case .leaveNow: now
        case let .departAt(date): date
        case let .arriveBy(date): date.addingTimeInterval(-duration)
        }
        let id = "veloh-\(origin.id)-\(destination.id)-\(pickup.id)-\(dropoff.id)"
        let bikeStart = start.addingTimeInterval(accessSeconds)
        let bikeEnd = bikeStart.addingTimeInterval(rideSeconds)
        let warning = (pickup.bikesAvailable.map { $0 <= 0 } ?? true)
            || (dropoff.docksAvailable.map { $0 <= 0 } ?? true)
            || [pickup, dropoff].contains { station in
                station.lastUpdated.map { now.timeIntervalSince($0) > 300 } ?? true
            }
        let legs = [
            RoutePlan.Leg(id: "\(id)-access", mode: .walking, transportKind: .walking,
                origin: origin, destination: pickup.location, departureTime: start, arrivalTime: bikeStart,
                distanceMeters: access.distanceMeters, mapCoordinates: access.coordinates),
            RoutePlan.Leg(id: "\(id)-ride", mode: .bicycle, instruction: "Take a vel’OH! bike",
                transportKind: .bikeShare, routeName: "vel’OH!", origin: pickup.location,
                destination: dropoff.location, departureTime: bikeStart, arrivalTime: bikeEnd,
                distanceMeters: ride.distanceMeters, mapCoordinates: ride.coordinates,
                roadRoutingHint: .bicycle, bikeShareDetails: .init(pickupStation: pickup,
                    returnStation: dropoff, isAvailabilityWarning: warning),
                mapStops: [
                    .init(id: "pickup", stopID: pickup.id, name: pickup.name, coordinate: RouteMapCoordinate(pickup.location)),
                    .init(id: "return", stopID: dropoff.id, name: dropoff.name, coordinate: RouteMapCoordinate(dropoff.location))
                ]),
            RoutePlan.Leg(id: "\(id)-egress", mode: .walking, transportKind: .walking,
                origin: dropoff.location, destination: destination, departureTime: bikeEnd,
                arrivalTime: start.addingTimeInterval(duration), distanceMeters: egress.distanceMeters,
                mapCoordinates: egress.coordinates)
        ]
        return RouteOption(id: id, plan: RoutePlan(id: id, origin: origin, destination: destination,
            expectedTravelTime: duration, distanceMeters: access.distanceMeters + ride.distanceMeters + egress.distanceMeters,
            legs: legs, dataSource: .local), mapOverlay: RouteMapOverlayBuilder.itinerary(legs: legs))
    }
}
