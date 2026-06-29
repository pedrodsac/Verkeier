import Foundation
import Testing
@testable import LuxTransit

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

    @Test func shareTextIncludesEndpointsLineAndAttribution() {
        let text = option(legs: [leg(from: hamilius, to: luxexpo)])
            .shareText(originTitle: "Home", destinationTitle: "Work")
        #expect(text.contains("Home → Work"))
        #expect(text.contains("Bus 16"))
        #expect(text.contains("LuxTransit"))
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
}
