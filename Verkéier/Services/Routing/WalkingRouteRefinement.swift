import Foundation
import MobiliteitKit

nonisolated struct WalkingGeometryRequest: Sendable {
    let origin: LocationPoint
    let destination: LocationPoint

    nonisolated var key: String {
        "\(origin.latitude),\(origin.longitude)|\(destination.latitude),\(destination.longitude)"
    }
}

nonisolated struct WalkingLegSpan: Sendable {
    let range: Range<Int>
    let request: WalkingGeometryRequest
    let needsRouting: Bool

    static func spans(in legs: [RoutePlan.Leg]) -> [Self] {
        var spans: [Self] = []
        var index = 0
        while index < legs.count {
            guard legs[index].transportKind == .walking else { index += 1; continue }
            let start = index
            while index < legs.count, legs[index].transportKind == .walking { index += 1 }
            let last = legs[index - 1]
            spans.append(Self(
                range: start..<index,
                request: WalkingGeometryRequest(origin: legs[start].origin, destination: last.destination),
                needsRouting: index - start > 1 || legs[start].roadRoutingHint == .walking
            ))
        }
        return spans
    }
}

extension RouteOption {
    /// Combines independently delivered transit shapes and walking refinements
    /// without letting either update erase the other one's legs.
    nonisolated func replacingLegs(
        of kind: RouteLegTransportKind,
        from updated: RouteOption,
        preserveUpdatedTotals: Bool = false
    ) -> RouteOption {
        guard id == updated.id else { return self }
        if kind == .walking {
            // A direct pedestrian route can replace several walking legs with
            // one. Use its leg sequence, retaining any newer transit shapes.
            let currentTransitByID = Dictionary(
                plan.legs.filter { $0.transportKind == .transit }.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let legs = updated.plan.legs.map { leg in
                leg.transportKind == .transit ? currentTransitByID[leg.id] ?? leg : leg
            }
            return replacingLegs(
                legs,
                expectedTravelTime: preserveUpdatedTotals ? updated.plan.expectedTravelTime : nil,
                distanceMeters: preserveUpdatedTotals ? updated.plan.distanceMeters : nil
            )
        }
        let updatedByID = Dictionary(
            updated.plan.legs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let legs = plan.legs.map { leg in
            guard leg.transportKind == kind,
                  let replacement = updatedByID[leg.id],
                  replacement.transportKind == kind
            else { return leg }
            return replacement
        }
        return replacingLegs(
            legs,
            expectedTravelTime: preserveUpdatedTotals ? updated.plan.expectedTravelTime : nil,
            distanceMeters: preserveUpdatedTotals ? updated.plan.distanceMeters : nil
        )
    }

    nonisolated func replacingWalkingRoutes(routesByLeg: [String: RoadRoute]) -> RouteOption {
        var legs: [RoutePlan.Leg] = []
        let original = plan.legs
        let spans = WalkingLegSpan.spans(in: original)
        func usableDirectRoute(for span: WalkingLegSpan) -> RoadRoute? {
            guard span.range.count > 1,
                  let route = routesByLeg[span.request.key],
                  let seconds = route.expectedTravelTime,
                  seconds.isFinite, seconds >= 0,
                  route.distanceMeters.isFinite, route.distanceMeters >= 0,
                  route.walkingEvidence == .routedPedestrian,
                  route.coordinates.count >= 2 else { return nil }
            return route
        }
        guard spans.contains(where: { span in
            usableDirectRoute(for: span) != nil
                || (span.range.count == 1 && span.needsRouting
                    && routesByLeg[span.request.key] != nil)
        }) else { return self }

        var cursor = 0
        for span in spans {
            legs.append(contentsOf: original[cursor..<span.range.lowerBound])
            let source = original[span.range.lowerBound]
            let end = original[span.range.upperBound - 1]
            if let directRoute = usableDirectRoute(for: span) {
                var merged = RoutePlan.Leg(
                    id: source.id, mode: .walking, instruction: source.instruction,
                    transportKind: .walking, origin: source.origin, destination: end.destination,
                    departureTime: source.departureTime, arrivalTime: end.arrivalTime,
                    distanceMeters: directRoute.distanceMeters,
                    mapCoordinates: directRoute.coordinates, roadRoutingHint: .walking
                )
                merged.departureTimingSource = source.departureTimingSource
                merged.arrivalTimingSource = end.arrivalTimingSource
                merged.walkingEvidence = .routedPedestrian
                let nativeRanges = original[span.range].compactMap(\.nativeWalkingRange)
                if let first = nativeRanges.first, let last = nativeRanges.last {
                    merged.nativeWalkingRange = first.lowerBound..<last.upperBound
                }
                legs.append(merged)
            } else {
                legs.append(contentsOf: original[span.range])
            }
            cursor = span.range.upperBound
        }
        legs.append(contentsOf: original[cursor...])

        func route(for leg: RoutePlan.Leg) -> RoadRoute? {
            guard leg.roadRoutingHint == .walking else { return nil }
            return routesByLeg[WalkingGeometryRequest(origin: leg.origin, destination: leg.destination).key]
        }
        func duration(_ leg: RoutePlan.Leg) -> TimeInterval {
            if let value = route(for: leg)?.expectedTravelTime, value.isFinite, value >= 0 {
                return value
            }
            return max(0, (leg.arrivalTime ?? .distantPast)
                .timeIntervalSince(leg.departureTime ?? .distantPast))
        }
        func replace(_ leg: RoutePlan.Leg, from departure: Date, through arrival: Date) -> RoutePlan.Leg {
            let geometry = route(for: leg)
            var updated = RoutePlan.Leg(
                id: leg.id, mode: leg.mode, instruction: leg.instruction,
                transportKind: leg.transportKind, routeName: leg.routeName,
                headsign: leg.headsign, routeId: leg.routeId, tripId: leg.tripId,
                originStopId: leg.originStopId, destinationStopId: leg.destinationStopId,
                stopCount: leg.stopCount, origin: leg.origin, destination: leg.destination,
                departureTime: departure, arrivalTime: arrival,
                scheduledDepartureTime: departure, scheduledArrivalTime: arrival,
                realtimeDepartureTime: leg.realtimeDepartureTime,
                realtimeArrivalTime: leg.realtimeArrivalTime,
                distanceMeters: geometry?.distanceMeters ?? leg.distanceMeters,
                mapCoordinates: geometry?.coordinates ?? leg.mapCoordinates,
                roadRoutingHint: leg.roadRoutingHint, platform: leg.platform,
                delayMinutes: leg.delayMinutes, liveStatus: leg.liveStatus,
                transferWarning: leg.transferWarning,
                bikeShareDetails: leg.bikeShareDetails
            )
            updated.departureTimingSource = leg.departureTimingSource
            updated.arrivalTimingSource = leg.arrivalTimingSource
            updated.requiredTransferSeconds = leg.requiredTransferSeconds
            updated.requiredTotalTransferSeconds = leg.requiredTotalTransferSeconds
            updated.continuesInSeatFromTripID = leg.continuesInSeatFromTripID
            updated.transitInstanceKey = leg.transitInstanceKey
            updated.boardingStopSequence = leg.boardingStopSequence
            updated.alightingStopSequence = leg.alightingStopSequence
            updated.walkingEvidence = geometry?.walkingEvidence ?? leg.walkingEvidence
            updated.nativeWalkingRange = leg.nativeWalkingRange
            return updated
        }

        var index = 0
        while index < legs.count {
            guard legs[index].transportKind == .walking else { index += 1; continue }
            let start = index
            while index < legs.count && legs[index].transportKind == .walking { index += 1 }
            let end = index
            guard (start..<end).contains(where: { route(for: legs[$0]) != nil }) else { continue }

            if start == 0 && end < legs.count && legs[end].transportKind == .transit,
               let boarding = legs[end].realtimeDepartureTime ?? legs[end].departureTime {
                var cursor = boarding
                for position in (start..<end).reversed() {
                    let departure = cursor.addingTimeInterval(-duration(legs[position]))
                    legs[position] = replace(legs[position], from: departure, through: cursor)
                    cursor = departure
                }
            } else if let firstDeparture = start == 0
                ? legs[start].departureTime
                : (legs[start - 1].realtimeArrivalTime ?? legs[start - 1].arrivalTime) {
                var cursor = firstDeparture
                for position in start..<end {
                    let arrival = cursor.addingTimeInterval(duration(legs[position]))
                    legs[position] = replace(legs[position], from: cursor, through: arrival)
                    cursor = arrival
                }
            }
        }
        let first = legs.first?.realtimeDepartureTime ?? legs.first?.departureTime
        let last = legs.last?.realtimeArrivalTime ?? legs.last?.arrivalTime
        let elapsed = first.flatMap { departure in last.map { max(0, $0.timeIntervalSince(departure)) } }
        let distance = legs.filter { $0.transportKind == .walking }
            .compactMap(\.distanceMeters).reduce(0, +)
        var transferWalk = 0.0
        var hasIncoming = false
        for index in legs.indices {
            if legs[index].transportKind == .walking, hasIncoming {
                transferWalk += max(0, (legs[index].arrivalTime ?? .distantPast).timeIntervalSince(legs[index].departureTime ?? .distantPast))
            } else if legs[index].transportKind == .transit {
                if hasIncoming, legs[index].continuesInSeatFromTripID == nil, let total = legs[index].requiredTotalTransferSeconds {
                    legs[index].requiredTransferSeconds = JourneyTransferArithmetic.requiredAfterWalking(totalMinimum: total, walkingSeconds: transferWalk)
                }
                hasIncoming = true; transferWalk = 0
            }
        }
        return replacingLegs(legs, expectedTravelTime: elapsed,
                             distanceMeters: distance)
    }

    nonisolated func replacingLegs(
        _ legs: [RoutePlan.Leg],
        expectedTravelTime: TimeInterval? = nil,
        distanceMeters: Double? = nil
    ) -> RouteOption {
        let updatedPlan = RoutePlan(
            id: plan.id,
            origin: plan.origin,
            destination: plan.destination,
            expectedTravelTime: expectedTravelTime ?? plan.expectedTravelTime,
            distanceMeters: distanceMeters ?? plan.distanceMeters,
            legs: legs,
            dataSource: plan.dataSource
        )
        let overlay = RouteMapOverlay(segments: legs.compactMap { leg in
            guard leg.mapCoordinates.count >= 2 else { return nil }
            return RouteMapSegment(
                id: leg.id,
                mode: leg.mode,
                routeName: leg.routeName,
                routeId: leg.routeId,
                coordinates: leg.mapCoordinates
            )
        })
        return RouteOption(id: id, plan: updatedPlan, mapOverlay: overlay.isEmpty ? nil : overlay,
                           feasibility: feasibility, statusEvidence: statusEvidence, refinementToken: refinementToken)
    }

}
