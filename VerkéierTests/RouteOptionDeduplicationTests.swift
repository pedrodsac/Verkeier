import Foundation
import Testing
@testable import Verkeier

@Suite("Equivalent route option deduplication")
@MainActor
struct RouteOptionDeduplicationTests {
    private let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.13)
    private let transferA = LocationPoint(name: "Transfer A", latitude: 49.62, longitude: 6.14)
    private let transferB = LocationPoint(name: "Transfer B", latitude: 49.63, longitude: 6.15)
    private let destination = LocationPoint(name: "Destination", latitude: 49.64, longitude: 6.16)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // Route quality now retains distinct itineraries even when card minutes
    // match. The previous safest-transfer-only collapse hid useful choices.
    @Test("Distinct transfers survive the same displayed time")
    func retainsDistinctTransferChoices() {
        let tight = option(id: "tight", transferGaps: [3 * 60, 12 * 60])
        let safe = option(id: "safe", transferGaps: [7 * 60, 8 * 60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([tight, safe])

        #expect(result.map(\.id) == ["tight", "safe"])
        #expect(safe.minimumTransferGapDuration == 420.0)
        #expect(safe.totalTransferGapDuration == 900.0)
    }

    @Test("Equal minimum gaps can represent distinct itineraries")
    func equalMinimumGapsRemainDistinct() {
        let shorterTotal = option(id: "shorter", transferGaps: [5 * 60, 6 * 60])
        let longerTotal = option(id: "longer", transferGaps: [5 * 60, 10 * 60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([shorterTotal, longerTotal])

        #expect(result.map(\.id) == ["shorter", "longer"])
    }

    @Test("A direct route survives beside a transfer")
    func directRouteSurvives() {
        let transfer = option(id: "transfer", transferGaps: [10 * 60])
        let direct = option(id: "direct", transferGaps: [])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([transfer, direct])

        #expect(result.map(\.id) == ["transfer", "direct"])
    }

    @Test("Same 326 and T1 trips show only the option without an intermediate 850 ride")
    func redundantIntermediateRideIsHidden() {
        let firstDeparture = start.addingTimeInterval(6 * 60)
        let arrival = start.addingTimeInterval(28 * 60)
        let detour = routeOption(id: "326-850-T1", legs: [
            walkingLeg(id: "access-detour", departure: start, duration: 6 * 60, distance: 556),
            transitLeg(id: "326", from: origin, to: transferA,
                       departure: firstDeparture, arrival: start.addingTimeInterval(12 * 60),
                       tripId: "326-trip", originStopId: "board-326", destinationStopId: "early-stop"),
            transitLeg(id: "850", from: transferA, to: transferB,
                       departure: start.addingTimeInterval(13 * 60),
                       arrival: start.addingTimeInterval(18 * 60), tripId: "850-trip"),
            transitLeg(id: "T1", from: transferB, to: destination,
                       departure: start.addingTimeInterval(21 * 60), arrival: arrival,
                       tripId: "T1-trip", originStopId: "tram-stop", destinationStopId: "final-stop"),
        ], duration: 28 * 60)
        let simpler = routeOption(id: "326-T1", legs: [
            walkingLeg(id: "access-simple", departure: start.addingTimeInterval(20),
                       duration: 5 * 60 + 40, distance: 569),
            transitLeg(id: "326", from: origin, to: transferB,
                       departure: firstDeparture, arrival: start.addingTimeInterval(19 * 60),
                       tripId: "326-trip", originStopId: "board-326", destinationStopId: "later-stop"),
            transitLeg(id: "T1", from: transferB, to: destination,
                       departure: start.addingTimeInterval(21 * 60), arrival: arrival,
                       tripId: "T1-trip", originStopId: "tram-stop", destinationStopId: "final-stop"),
        ], duration: 28 * 60)

        #expect(detour.transferCount == 2)
        #expect(simpler.transferCount == 1)
        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([detour, simpler]).map(\.id)
                == [simpler.id])
        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([simpler, detour]).map(\.id)
                == [simpler.id])
    }

    @Test("Different first or last trips remain separate despite matching line labels and times")
    func differentTripIdentityRemainsDistinct() {
        let first = routeOption(id: "first", legs: [
            transitLeg(id: "326", from: origin, to: transferA,
                       departure: start, arrival: start.addingTimeInterval(10 * 60),
                       tripId: "326-trip-a", originStopId: "board-326"),
            transitLeg(id: "850", from: transferA, to: transferB,
                       departure: start.addingTimeInterval(12 * 60),
                       arrival: start.addingTimeInterval(20 * 60)),
            transitLeg(id: "T1", from: transferB, to: destination,
                       departure: start.addingTimeInterval(22 * 60),
                       arrival: start.addingTimeInterval(28 * 60),
                       tripId: "T1-trip", destinationStopId: "final-stop"),
        ])
        let second = routeOption(id: "second", legs: [
            transitLeg(id: "326", from: origin, to: transferB,
                       departure: start, arrival: start.addingTimeInterval(20 * 60),
                       tripId: "326-trip-b", originStopId: "board-326"),
            transitLeg(id: "T1", from: transferB, to: destination,
                       departure: start.addingTimeInterval(22 * 60),
                       arrival: start.addingTimeInterval(28 * 60),
                       tripId: "T1-trip", destinationStopId: "final-stop"),
        ])

        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([first, second]).map(\.id)
                == [first.id, second.id])
    }

    @Test("A later departure with the same arrival removes slower alternatives")
    func laterDepartureDominates() {
        let baseline = option(id: "baseline", transferGaps: [5 * 60])
        let departure = option(id: "departure", transferGaps: [5 * 60], departureOffset: 60)
        let arrival = option(id: "arrival", transferGaps: [5 * 60], arrivalOffset: 60)
        let duration = option(id: "duration", transferGaps: [5 * 60], duration: 47 * 60)

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([
            baseline, departure, arrival, duration,
        ])

        #expect(result.map(\.id) == ["departure"])
    }

    @Test("A later, earlier-arriving route hides the enclosing route despite more walking")
    func enclosedRouteIsHidden() {
        let slower = routeOption(id: "10:57-11:52", legs: [
            walkingLeg(id: "slow-access", departure: start, duration: 9 * 60, distance: 755),
            transitLeg(id: "850", from: transferA, to: transferB,
                       departure: start.addingTimeInterval(9 * 60),
                       arrival: start.addingTimeInterval(20 * 60)),
            transitLeg(id: "3", from: transferB, to: transferA,
                       departure: start.addingTimeInterval(22 * 60),
                       arrival: start.addingTimeInterval(35 * 60)),
            transitLeg(id: "12", from: transferA, to: destination,
                       departure: start.addingTimeInterval(37 * 60),
                       arrival: start.addingTimeInterval(55 * 60)),
        ])
        let faster = routeOption(id: "10:58-11:29", legs: [
            walkingLeg(id: "fast-access", departure: start.addingTimeInterval(60),
                       duration: 10 * 60, distance: 829),
            transitLeg(id: "29", from: transferA, to: transferB,
                       departure: start.addingTimeInterval(11 * 60),
                       arrival: start.addingTimeInterval(20 * 60)),
            transitLeg(id: "6", from: transferB, to: destination,
                       departure: start.addingTimeInterval(22 * 60),
                       arrival: start.addingTimeInterval(32 * 60)),
        ])

        #expect(slower.walkingDistanceMeters < faster.walkingDistanceMeters)
        #expect(slower.transferCount > faster.transferCount)
        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([slower, faster]).map(\.id)
                == [faster.id])
        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([faster, slower]).map(\.id)
                == [faster.id])
    }

    @Test("A cancelled itinerary remains visible beside a usable route")
    func cancelledRouteIsRetained() {
        let cancelled = routeOption(id: "cancelled", legs: [
            transitLeg(id: "cancelled-line", from: origin, to: destination,
                       departure: start, arrival: start.addingTimeInterval(45 * 60),
                       liveStatus: .cancelled),
        ])
        let usable = routeOption(id: "usable", legs: [
            transitLeg(id: "usable-line", from: origin, to: destination,
                       departure: start.addingTimeInterval(60),
                       arrival: start.addingTimeInterval(40 * 60)),
        ])

        #expect(cancelled.status(at: start) == .cancelled)
        #expect(TransitMapViewModel.deduplicatingEquivalentRouteOptions([cancelled, usable]).map(\.id)
                == ["cancelled", "usable"])
    }

    @Test("A replacement route shares the first bus and keeps the cancelled route visible")
    func sharedFirstBusReplacementIsRetained() {
        let firstBus = transitLeg(id: "first-bus", from: origin, to: transferA,
                                  departure: start, arrival: start.addingTimeInterval(10 * 60))
        let cancelled = routeOption(id: "cancelled-transfer", legs: [
            firstBus,
            transitLeg(id: "cancelled-second", from: transferA, to: destination,
                       departure: start.addingTimeInterval(15 * 60),
                       arrival: start.addingTimeInterval(25 * 60), liveStatus: .cancelled),
        ])
        let replacement = routeOption(id: "replacement-transfer", legs: [
            firstBus,
            transitLeg(id: "replacement-second", from: transferA, to: destination,
                       departure: start.addingTimeInterval(20 * 60),
                       arrival: start.addingTimeInterval(35 * 60)),
        ])
        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([
            cancelled, replacement,
        ])
        #expect(result.map(\.id) == ["cancelled-transfer", "replacement-transfer"])
    }

    @Test("Second-level differences within a display minute survive")
    func sameDisplayedMinuteSurvives() {
        let first = option(id: "first", transferGaps: [4 * 60])
        let safer = option(
            id: "safer",
            transferGaps: [9 * 60],
            departureOffset: 20,
            arrivalOffset: 20,
            duration: 45 * 60 + 20
        )

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([first, safer])

        #expect(result.map(\.id) == ["first", "safer"])
    }

    @Test("Unknown and known transfer timings remain distinct")
    func knownAndUnknownTimingRemainDistinct() {
        let unknown = option(id: "unknown", transferGaps: [nil])
        let known = option(id: "known", transferGaps: [-60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([unknown, known])

        #expect(result.map(\.id) == ["unknown", "known"])
        #expect(known.minimumTransferGapDuration == -60)
    }

    @Test("Transfer gaps span an intervening walking leg")
    func transferGapIncludesInterveningWalk() {
        let firstArrival = start.addingTimeInterval(10 * 60)
        let nextDeparture = start.addingTimeInterval(20 * 60)
        let firstRide = transitLeg(
            id: "first-ride",
            from: origin,
            to: transferA,
            departure: start,
            arrival: firstArrival
        )
        let walk = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: transferA,
            destination: transferB,
            departureTime: firstArrival,
            arrivalTime: firstArrival.addingTimeInterval(4 * 60)
        )
        let secondRide = transitLeg(
            id: "second-ride",
            from: transferB,
            to: destination,
            departure: nextDeparture,
            arrival: start.addingTimeInterval(45 * 60)
        )
        let route = routeOption(id: "walking-transfer", legs: [firstRide, walk, secondRide])

        #expect(route.transferGapDurations == [10 * 60])
    }

    @Test("Incomplete card timing is never grouped")
    func incompleteCardTimingRemainsSeparate() {
        let first = option(id: "first", transferGaps: [5 * 60], hasArrival: false)
        let second = option(id: "second", transferGaps: [10 * 60], hasArrival: false)

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([first, second])

        #expect(result.map(\.id) == ["first", "second"])
    }

    @Test("Non-transit alternatives are not collapsed with transit results")
    func nonTransitAlternativesRemainSeparate() {
        let walkingLeg = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: start,
            arrivalTime: start.addingTimeInterval(45 * 60)
        )
        let first = routeOption(id: "walk-a", legs: [walkingLeg])
        let second = routeOption(id: "walk-b", legs: [walkingLeg])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([first, second])

        #expect(result.map(\.id) == ["walk-a", "walk-b"])
    }

    @Test("Distinct identities preserve input order through deduplication")
    func exactTieIsDeterministicAndStable() {
        let laterGroup = option(
            id: "later-group",
            transferGaps: [5 * 60],
            departureOffset: 5 * 60,
            arrivalOffset: 5 * 60
        )
        let higherID = option(id: "z-route", transferGaps: [5 * 60])
        let lowerID = option(id: "a-route", transferGaps: [5 * 60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([
            higherID, laterGroup, lowerID,
        ])

        #expect(result.map(\.id) == ["z-route", "later-group", "a-route"])
    }

    @Test("Repeated stable identity keeps the safer update in its original position")
    func duplicateIdentityUsesSaferUpdate() {
        let tight = option(id: "same", transferGaps: [3 * 60])
        let safe = option(id: "same", transferGaps: [9 * 60])
        let other = option(id: "other", transferGaps: [])
        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([tight, other, safe])
        #expect(result.map(\.id) == ["same", "other"])
        #expect(result[0].minimumTransferGapDuration == 540.0)
    }

    private func option(
        id: String,
        transferGaps: [TimeInterval?],
        departureOffset: TimeInterval = 0,
        arrivalOffset: TimeInterval = 0,
        duration: TimeInterval = 45 * 60,
        hasDeparture: Bool = true,
        hasArrival: Bool = true
    ) -> RouteOption {
        let routeDeparture = start.addingTimeInterval(departureOffset)
        let routeArrival = start.addingTimeInterval(45 * 60 + arrivalOffset)
        let points = [origin, transferA, transferB, destination]
        var legs: [RoutePlan.Leg] = []

        if transferGaps.isEmpty {
            legs.append(transitLeg(
                id: "\(id)-direct",
                from: origin,
                to: destination,
                departure: hasDeparture ? routeDeparture : nil,
                arrival: hasArrival ? routeArrival : nil
            ))
        } else {
            let rideDuration: TimeInterval = 5 * 60
            var departure = routeDeparture
            for index in 0 ... transferGaps.count {
                let isLast = index == transferGaps.count
                let arrival = isLast ? (hasArrival ? routeArrival : nil) : departure.addingTimeInterval(rideDuration)
                legs.append(transitLeg(
                    id: "\(id)-\(index)",
                    from: points[index],
                    to: points[index + 1],
                    departure: departure,
                    arrival: arrival
                ))
                if !isLast {
                    if let gap = transferGaps[index], let arrival {
                        departure = arrival.addingTimeInterval(gap)
                    } else {
                        departure = routeDeparture.addingTimeInterval(TimeInterval((index + 1) * 10 * 60))
                    }
                }
            }
        }

        if transferGaps.contains(where: { $0 == nil }), legs.count > 1 {
            let last = legs.removeLast()
            legs.append(transitLeg(
                id: last.id,
                from: last.origin,
                to: last.destination,
                departure: nil,
                arrival: last.arrivalTime
            ))
        }

        return routeOption(id: id, legs: legs, duration: duration)
    }

    private func routeOption(
        id: String,
        legs: [RoutePlan.Leg],
        duration: TimeInterval = 45 * 60
    ) -> RouteOption {
        RouteOption(
            id: id,
            plan: RoutePlan(
                id: "plan-\(id)",
                origin: origin,
                destination: destination,
                expectedTravelTime: duration,
                distanceMeters: 1_000,
                legs: legs,
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }

    private func transitLeg(
        id: String,
        from origin: LocationPoint,
        to destination: LocationPoint,
        departure: Date?,
        arrival: Date?,
        liveStatus: RouteLegLiveStatus = .scheduled,
        tripId: String? = nil,
        originStopId: String? = nil,
        destinationStopId: String? = nil
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: .bus,
            transportKind: .transit,
            routeName: id,
            tripId: tripId,
            originStopId: originStopId,
            destinationStopId: destinationStopId,
            origin: origin,
            destination: destination,
            departureTime: departure,
            arrivalTime: arrival,
            liveStatus: liveStatus
        )
    }

    private func walkingLeg(
        id: String,
        departure: Date,
        duration: TimeInterval,
        distance: Double
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: transferA,
            departureTime: departure,
            arrivalTime: departure.addingTimeInterval(duration),
            distanceMeters: distance
        )
    }
}
