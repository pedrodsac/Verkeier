import Foundation
import Testing
@testable import Verkeier

struct RouteOptionTests {
    private func leg(
        from: LocationPoint,
        to: LocationPoint,
        kind: RouteLegTransportKind = .transit,
        routeName: String? = "Bus 16"
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: "leg",
            mode: .bus,
            transportKind: kind,
            routeName: routeName,
            origin: from,
            destination: to,
            departureTime: Date(timeIntervalSince1970: 1000),
            arrivalTime: Date(timeIntervalSince1970: 1600),
            distanceMeters: 1000
        )
    }

    private func option(legs: [RoutePlan.Leg]) -> RouteOption {
        let plan = RoutePlan(
            id: "p",
            origin: legs.first!.origin,
            destination: legs.last!.destination,
            expectedTravelTime: 600,
            distanceMeters: 1000,
            legs: legs,
            dataSource: .mock
        )
        return RouteOption(id: "o", plan: plan, mapOverlay: nil)
    }

    private let hamilius = LocationPoint(name: "Hamilius", latitude: 49.6115, longitude: 6.126)
    private let luxexpo = LocationPoint(name: "Luxexpo", latitude: 49.633, longitude: 6.175)
    private let metz = LocationPoint(name: "Metz", latitude: 49.11, longitude: 6.176)

    @Test func domesticRouteDoesNotCrossBorder() {
        #expect(option(legs: [leg(from: hamilius, to: luxexpo)]).crossesBorder == false)
    }

    @Test func routeIntoFranceCrossesBorder() {
        #expect(option(legs: [leg(from: hamilius, to: metz)]).crossesBorder == true)
    }

    @Test func walkingOnlyRequiresEveryLegToBeWalking() {
        let walking = leg(from: hamilius, to: luxexpo, kind: .walking, routeName: nil)
        #expect(option(legs: [walking]).isWalkingOnly)
        #expect(!option(legs: [walking, leg(from: hamilius, to: luxexpo)]).isWalkingOnly)
    }

    @Test func shareTextIncludesEndpointsLineAndAttribution() {
        let text = option(legs: [leg(from: hamilius, to: luxexpo)])
            .shareText(originTitle: "Home", destinationTitle: "Work")
        #expect(text.contains("Home → Work"))
        #expect(text.contains("Bus 16"))
        #expect(text.contains("Verkéier"))
    }

    // MARK: - Transfer reliability / status

    private func transitLeg(
        from: LocationPoint,
        to: LocationPoint,
        departure: Date,
        liveStatus: RouteLegLiveStatus = .scheduled,
        transferWarning: String? = nil
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: "leg-\(departure.timeIntervalSince1970)",
            mode: .bus,
            transportKind: .transit,
            routeName: "16",
            origin: from,
            destination: to,
            departureTime: departure,
            arrivalTime: departure.addingTimeInterval(300),
            distanceMeters: 1000,
            liveStatus: liveStatus,
            transferWarning: transferWarning
        )
    }

    @Test func tightTransferMakesOptionAtRisk() {
        let now = Date(timeIntervalSince1970: 10000)
        let future = now.addingTimeInterval(600)
        let legs = [
            transitLeg(from: hamilius, to: luxexpo, departure: future, liveStatus: .live),
            transitLeg(
                from: luxexpo, to: hamilius, departure: future.addingTimeInterval(400),
                transferWarning: "Tight connection — 1 min to change"
            )
        ]
        #expect(option(legs: legs).status(at: now) == .atRisk)
    }

    @Test func mixedLiveAndScheduledLegsAreFlaggedPartlyLive() {
        let now = Date(timeIntervalSince1970: 10_000)
        let future = now.addingTimeInterval(600)
        let route = option(legs: [
            transitLeg(from: hamilius, to: luxexpo, departure: future, liveStatus: .live),
            transitLeg(from: luxexpo, to: hamilius, departure: future.addingTimeInterval(600))
        ])

        #expect(route.realtimeCoverage == .partial)
        #expect(route.status(at: now) == .partiallyLive)
        #expect(route.status(at: now).displayText == "Partly live")
    }

    @Test func missedConnectionMakesOptionConnectionMayBeMissed() {
        let now = Date(timeIntervalSince1970: 10000)
        let future = now.addingTimeInterval(600)
        let legs = [
            transitLeg(from: hamilius, to: luxexpo, departure: future, liveStatus: .live),
            transitLeg(
                from: luxexpo, to: hamilius, departure: future.addingTimeInterval(400),
                transferWarning: "Connection miss"
            )
        ]

        let route = option(legs: legs)
        #expect(route.status(at: now) == .connectionMayBeMissed)
        #expect(route.status(at: now).displayText == "Connection miss")
    }

    @Test func cancelledLegMakesOptionCancelled() {
        let now = Date(timeIntervalSince1970: 10000)
        let leg = transitLeg(
            from: hamilius, to: luxexpo, departure: now.addingTimeInterval(600), liveStatus: .cancelled
        )
        #expect(option(legs: [leg]).status(at: now) == .cancelled)
    }

    @Test func pastFirstDepartureIsMissed() {
        let now = Date(timeIntervalSince1970: 10000)
        let leg = transitLeg(from: hamilius, to: luxexpo, departure: now.addingTimeInterval(-600))
        #expect(option(legs: [leg]).status(at: now) == .missed)
    }

    @Test func velohOnlyRouteShowsAsScheduledAfterItsDeparture() {
        let bike = RoutePlan.Leg(
            id: "veloh",
            mode: .bicycle,
            transportKind: .bikeShare,
            routeName: "vel’OH!",
            origin: hamilius,
            destination: luxexpo,
            departureTime: Date(timeIntervalSince1970: 1000),
            arrivalTime: Date(timeIntervalSince1970: 1600),
            distanceMeters: 1200
        )
        let route = option(legs: [bike])

        #expect(route.isVelohOnly)
        #expect(route.status(at: Date(timeIntervalSince1970: 10000)) == .scheduledOnly)
    }

    @Test func mixedVelohAndTransitRouteStillUsesTransitMissedStatus() {
        let now = Date(timeIntervalSince1970: 10000)
        let bike = RoutePlan.Leg(
            id: "veloh",
            mode: .bicycle,
            transportKind: .bikeShare,
            routeName: "vel’OH!",
            origin: hamilius,
            destination: luxexpo,
            departureTime: now.addingTimeInterval(-1200),
            arrivalTime: now.addingTimeInterval(-600),
            distanceMeters: 1200
        )
        let bus = transitLeg(
            from: luxexpo,
            to: hamilius,
            departure: now.addingTimeInterval(-500)
        )
        let route = option(legs: [bike, bus])

        #expect(!route.isVelohOnly)
        #expect(route.status(at: now) == .missed)
    }

    // MARK: - Door-to-door departure

    @Test func departureTimeIncludesLeadingAccessWalk() {
        // A journey that starts on foot: door-to-door departure is the walk's,
        // which is earlier than the first bus — the two must differ.
        let walk = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: hamilius,
            destination: luxexpo,
            departureTime: Date(timeIntervalSince1970: 1000),
            arrivalTime: Date(timeIntervalSince1970: 1300)
        )
        let ride = transitLeg(from: luxexpo, to: hamilius, departure: Date(timeIntervalSince1970: 1400))
        let o = option(legs: [walk, ride])
        #expect(o.departureTime == Date(timeIntervalSince1970: 1000)) // includes the walk
        #expect(o.firstTransitDepartureTime == Date(timeIntervalSince1970: 1400)) // still the bus
    }

    @Test func departureTimeIsFirstTransitWhenNoAccessWalk() {
        let ride = transitLeg(from: hamilius, to: luxexpo, departure: Date(timeIntervalSince1970: 2000))
        #expect(option(legs: [ride]).departureTime == Date(timeIntervalSince1970: 2000))
    }

    @Test func departureTimePrefersRealtime() {
        let ride = RoutePlan.Leg(
            id: "ride",
            mode: .bus,
            transportKind: .transit,
            routeName: "16",
            origin: hamilius,
            destination: luxexpo,
            departureTime: Date(timeIntervalSince1970: 2000),
            arrivalTime: Date(timeIntervalSince1970: 2600),
            realtimeDepartureTime: Date(timeIntervalSince1970: 2120)
        )
        #expect(option(legs: [ride]).departureTime == Date(timeIntervalSince1970: 2120))
    }

    @Test func departureTimeIsNilWithoutLegs() {
        let plan = RoutePlan(
            id: "empty",
            origin: hamilius,
            destination: luxexpo,
            expectedTravelTime: nil,
            distanceMeters: nil,
            legs: [],
            dataSource: .mock
        )
        #expect(RouteOption(id: "o", plan: plan, mapOverlay: nil).departureTime == nil)
    }
}
