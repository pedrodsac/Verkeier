import Foundation
import Testing
@testable import Verkeier

struct BikeShareTests {
    private let origin = LocationPoint(id: "origin", name: "Origin", latitude: 49.6116, longitude: 6.1319)
    private let destination = LocationPoint(id: "destination", name: "Destination", latitude: 49.6200, longitude: 6.1500)

    private func station(
        _ id: String,
        name: String,
        bikes: Int? = 4,
        docks: Int? = 8,
        latitude: Double,
        longitude: Double
    ) -> BikeShareStation {
        BikeShareStation(
            id: id,
            name: name,
            location: LocationPoint(id: id, name: name, latitude: latitude, longitude: longitude),
            bikesAvailable: bikes,
            docksAvailable: docks,
            capacity: 20,
            isOpen: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
    }

    private func bikeOption(details: BikeShareLegDetails) -> RouteOption {
        let leg = RoutePlan.Leg(
            id: "bike",
            mode: .bicycle,
            instruction: "Take a vel’OH! bike",
            transportKind: .bikeShare,
            routeName: "vel’OH!",
            origin: details.pickupStation.location,
            destination: details.returnStation.location,
            departureTime: Date(timeIntervalSince1970: 1000),
            arrivalTime: Date(timeIntervalSince1970: 1300),
            distanceMeters: 1200,
            bikeShareDetails: details
        )
        return RouteOption(
            id: "bike-option",
            plan: RoutePlan(
                id: "bike-plan",
                origin: origin,
                destination: destination,
                expectedTravelTime: 300,
                distanceMeters: 1200,
                legs: [leg],
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }

    @Test func zeroAvailabilityIsMarkedAsWarningButRouteRemainsSelectable() {
        let details = BikeShareLegDetails(
            pickupStation: station("1", name: "Pickup", bikes: 0, latitude: 49.611, longitude: 6.132),
            returnStation: station("2", name: "Return", docks: 0, latitude: 49.620, longitude: 6.150),
            isAvailabilityWarning: true
        )
        let option = bikeOption(details: details)
        #expect(option.usesBikeShare)
        #expect(option.hasBikeAvailabilityWarning)
        #expect(option.status(at: Date(timeIntervalSince1970: 0)) == .scheduledOnly)
    }

    @Test func timelineCarriesBikeStationCounts() {
        let details = BikeShareLegDetails(
            pickupStation: station("1", name: "Pickup", latitude: 49.611, longitude: 6.132),
            returnStation: station("2", name: "Return", latitude: 49.620, longitude: 6.150),
            isAvailabilityWarning: false
        )
        let leg = RoutePlan.Leg(
            id: "bike",
            mode: .bicycle,
            transportKind: .bikeShare,
            origin: details.pickupStation.location,
            destination: details.returnStation.location,
            departureTime: Date(timeIntervalSince1970: 1000),
            arrivalTime: Date(timeIntervalSince1970: 1300),
            distanceMeters: 1200,
            bikeShareDetails: details
        )
        let segment = RouteTimelineBuilder.items(from: [leg]).compactMap {
            if case let .segment(value) = $0 { value } else { nil }
        }.first
        #expect(segment?.kind == .bikeShare)
        #expect(segment?.bikeShareDetails == details)
        #expect(segment?.rail == .transit(.bicycle))

        let places = RouteTimelineBuilder.items(from: [leg]).compactMap {
            if case let .place(value) = $0 { value } else { nil }
        }
        #expect(places[0].bikeShareStationRole == .pickup)
        #expect(places[0].bikeShareStation?.bikesAvailable == 4)
        #expect(places[1].bikeShareStationRole == .returnStation)
        #expect(places[1].bikeShareStation?.docksAvailable == 8)
    }

    @Test func unavailableServiceIsSafeDefault() async {
        let service = UnavailableBikeShareService()
        #expect(await service.bikeShareStations(near: origin).isEmpty)
        #expect(await service.snapshot() == nil)
    }
}
