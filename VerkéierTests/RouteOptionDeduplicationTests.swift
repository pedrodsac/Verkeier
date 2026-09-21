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

    @Test("Equivalent cards retain the option with the largest minimum transfer gap")
    func retainsSafestMinimumTransferGap() {
        let tight = option(id: "tight", transferGaps: [3 * 60, 12 * 60])
        let safe = option(id: "safe", transferGaps: [7 * 60, 8 * 60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([tight, safe])

        #expect(result.map(\.id) == ["safe"])
        #expect(safe.minimumTransferGapDuration == 7 * 60)
        #expect(safe.totalTransferGapDuration == 15 * 60)
    }

    @Test("Total transfer time breaks an equal minimum-gap tie")
    func totalTransferTimeBreaksTie() {
        let shorterTotal = option(id: "shorter", transferGaps: [5 * 60, 6 * 60])
        let longerTotal = option(id: "longer", transferGaps: [5 * 60, 10 * 60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([shorterTotal, longerTotal])

        #expect(result.map(\.id) == ["longer"])
    }

    @Test("A direct route wins an equivalent group")
    func directRouteWins() {
        let transfer = option(id: "transfer", transferGaps: [10 * 60])
        let direct = option(id: "direct", transferGaps: [])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([transfer, direct])

        #expect(result.map(\.id) == ["direct"])
    }

    @Test("Different displayed timing values remain separate")
    func differentDisplayedValuesRemainSeparate() {
        let baseline = option(id: "baseline", transferGaps: [5 * 60])
        let departure = option(id: "departure", transferGaps: [5 * 60], departureOffset: 60)
        let arrival = option(id: "arrival", transferGaps: [5 * 60], arrivalOffset: 60)
        let duration = option(id: "duration", transferGaps: [5 * 60], duration: 47 * 60)

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([
            baseline, departure, arrival, duration,
        ])

        #expect(result.map(\.id) == ["baseline", "departure", "arrival", "duration"])
    }

    @Test("Second-level differences that display in the same minute collapse")
    func sameDisplayedMinuteCollapses() {
        let first = option(id: "first", transferGaps: [4 * 60])
        let safer = option(
            id: "safer",
            transferGaps: [9 * 60],
            departureOffset: 20,
            arrivalOffset: 20,
            duration: 45 * 60 + 20
        )

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([first, safer])

        #expect(result.map(\.id) == ["safer"])
    }

    @Test("Known transfer timing wins over unknown timing")
    func knownTimingWins() {
        let unknown = option(id: "unknown", transferGaps: [nil])
        let known = option(id: "known", transferGaps: [-60])

        let result = TransitMapViewModel.deduplicatingEquivalentRouteOptions([unknown, known])

        #expect(result.map(\.id) == ["known"])
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

    @Test("Exact ties use existing deterministic ranking and preserve group position")
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

        #expect(result.map(\.id) == ["a-route", "later-group"])
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
        arrival: Date?
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: .bus,
            transportKind: .transit,
            routeName: id,
            origin: origin,
            destination: destination,
            departureTime: departure,
            arrivalTime: arrival
        )
    }
}
