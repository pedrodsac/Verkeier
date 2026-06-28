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
}
