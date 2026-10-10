import Foundation
import Testing
@testable import Verkeier

struct BikeShareRoutePlannerTests {
    private let origin = LocationPoint(id: "origin", latitude: 49.6, longitude: 6.1)
    private let destination = LocationPoint(id: "destination", latitude: 49.61, longitude: 6.1)
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [RoutePlanningTime.leaveNow, .departAt(Date(timeIntervalSince1970: 1_800_000_000)),
                      .arriveBy(Date(timeIntervalSince1970: 1_800_000_000))])
    func createsDoorToDoorBikeOption(time: RoutePlanningTime) async throws {
        let planner = BikeShareRoutePlanner(stations: fixture(), roads: BikeFixtureRoads())
        let option = try #require(await planner.option(from: origin, to: destination, time: time, now: anchor))
        #expect(option.isVelohOnly)
        #expect(!option.hasBikeAvailabilityWarning)
        #expect(option.plan.legs.map(\.transportKind) == [.walking, .bikeShare, .walking])
        #expect(option.mapOverlay?.segments.count == 3)
        #expect(option.plan.expectedTravelTime == 480) // 2x60s walks + 1km at 15km/h + 120s.
        if case .arriveBy = time {
            #expect(option.arrivalTime == anchor)
            #expect(option.departureTime == anchor.addingTimeInterval(-480))
        } else {
            #expect(option.departureTime == anchor)
            #expect(option.arrivalTime == anchor.addingTimeInterval(480))
        }
        for pair in zip(option.plan.legs, option.plan.legs.dropFirst()) {
            #expect(pair.0.arrivalTime == pair.1.departureTime)
            #expect(pair.0.destination == pair.1.origin)
        }
    }

    @Test(arguments: [0, nil])
    func unavailableCountsWarnButRemainSelectable(count: Int?) async throws {
        let planner = BikeShareRoutePlanner(stations: fixture(count: count), roads: BikeFixtureRoads())
        let option = try #require(await planner.option(from: origin, to: destination, time: .leaveNow, now: anchor))
        #expect(option.hasBikeAvailabilityWarning)
        #expect(option.status(at: anchor).isSelectable)
    }

    @Test func missingClosedDistantOrSameStationCannotProduceRental() async {
        for stations in [[], fixture(open: false).values, [fixture().values[0]],
                         [station("far", latitude: 50)]] {
            let planner = BikeShareRoutePlanner(stations: BikeFixtureStations(values: stations), roads: BikeFixtureRoads())
            #expect(await planner.option(from: origin, to: destination, time: .leaveNow, now: anchor) == nil)
        }
    }

    @Test(arguments: [BikeFixtureRoads(fails: true), BikeFixtureRoads(estimated: true),
                      BikeFixtureRoads(walkDistance: 1_001), BikeFixtureRoads(rideDistance: 12_001)])
    func unroutableOrExcessivePathsDoNotProduceOption(roads: BikeFixtureRoads) async {
        let planner = BikeShareRoutePlanner(stations: fixture(), roads: roads)
        #expect(await planner.option(from: origin, to: destination, time: .leaveNow, now: anchor) == nil)
    }

    @Test func availableStationWinsOverCloserEmptyStation() async throws {
        var stations = fixture().values
        stations.insert(station("empty", latitude: origin.latitude, count: 0), at: 0)
        let planner = BikeShareRoutePlanner(stations: BikeFixtureStations(values: stations), roads: BikeFixtureRoads())
        let option = try #require(await planner.option(from: origin, to: destination, time: .leaveNow, now: anchor))
        #expect(option.plan.legs[1].bikeShareDetails?.pickupStation.id == "pickup")
        #expect(!option.hasBikeAvailabilityWarning)
    }

    @Test func completionOrderPreservesTieWinnerAndSharesEgress() async throws {
        let pickupA = station("pickup-a", latitude: 49.6001)
        let pickupB = station("pickup-b", latitude: 49.6002)
        let returnA = station("return-a", latitude: 49.6101)
        let returnB = station("return-b", latitude: 49.6102)
        let roads = ReorderedBikeRoads()
        let planner = BikeShareRoutePlanner(stations: BikeFixtureStations(
            values: [returnB, pickupB, returnA, pickupA]), roads: roads)
        let result = try #require(await planner.option(from: origin, to: destination,
            time: .departAt(anchor), now: anchor))
        let expected = await BikeShareRoutePlanner(stations: BikeFixtureStations(
            values: [pickupA, returnA]), roads: BikeFixtureRoads()).option(
                from: origin, to: destination, time: .departAt(anchor), now: anchor)
        #expect(result == expected)
        let counts = await roads.counts()
        #expect(counts.maximum == 2)
        #expect(counts.egress == 2)
        #expect(counts.total == 8)
    }

    @Test func cancelledWorkCannotPublishOption() async {
        let planner = BikeShareRoutePlanner(stations: fixture(), roads: BikeFixtureRoads())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await planner.option(from: origin, to: destination, time: .leaveNow, now: anchor)
        }
        #expect(await task.value == nil)
    }

    private func fixture(count: Int? = 4, open: Bool = true) -> BikeFixtureStations {
        BikeFixtureStations(values: [station("pickup", latitude: 49.6001, count: count, open: open),
                                     station("return", latitude: 49.6101, count: count, open: open)])
    }
    private func station(_ id: String, latitude: Double, count: Int? = 4, open: Bool = true) -> BikeShareStation {
        BikeShareStation(id: id, name: id, location: LocationPoint(id: id, latitude: latitude, longitude: 6.1),
            bikesAvailable: count, docksAvailable: count, isOpen: open, lastUpdated: anchor)
    }
}

nonisolated struct BikeFixtureStations: BikeShareService {
    let values: [BikeShareStation]
    func bikeShareStations(near location: LocationPoint) async -> [BikeShareStation] { values }
    func refreshStaticStations() async {}
    func refreshAvailability() async {}
    func snapshot() async -> BikeShareSnapshot? { nil }
}

nonisolated struct BikeFixtureRoads: RoadRouteProviding {
    var fails = false
    var estimated = false
    var walkDistance: Double = 100
    var rideDistance: Double = 1_000
    func roadRouteCoordinates(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> [RouteMapCoordinate]? {
        await roadRoute(from: from, to: to, transport: transport)?.coordinates
    }
    func roadRoute(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> RoadRoute? {
        guard !fails else { return nil }
        let ride = abs(from.latitude - to.latitude) > 0.002
        return RoadRoute(coordinates: [RouteMapCoordinate(from), RouteMapCoordinate(to)],
            distanceMeters: ride ? rideDistance : walkDistance, expectedTravelTime: ride ? 720 : 60,
            walkingEvidence: estimated ? .estimate : .routedPedestrian)
    }
}

/// Finish the second pickup first so task completion cannot choose a tie winner.
nonisolated private struct ReorderedBikeRoads: RoadRouteProviding {
    private let probe = BikeRoadProbe()
    func counts() async -> (maximum: Int, egress: Int, total: Int) { await probe.counts() }
    func roadRouteCoordinates(from: LocationPoint, to: LocationPoint,
                              transport: RoadRouteTransport) async -> [RouteMapCoordinate]? {
        await roadRoute(from: from, to: to, transport: transport)?.coordinates
    }
    func roadRoute(from: LocationPoint, to: LocationPoint,
                   transport: RoadRouteTransport) async -> RoadRoute? {
        await probe.route(from: from, to: to, transport: transport)
    }
}

private actor BikeRoadProbe {
    private var active = 0
    private var maximum = 0
    private var egress = 0
    private var total = 0
    func counts() -> (maximum: Int, egress: Int, total: Int) { (maximum, egress, total) }
    func route(from: LocationPoint, to: LocationPoint,
                   transport: RoadRouteTransport) async -> RoadRoute? {
        active += 1; total += 1; maximum = max(maximum, active)
        if to.id == "destination" { egress += 1 }
        defer { active -= 1 }
        try? await Task.sleep(for: .milliseconds(from.id == "pickup-a" ? 20 : 1))
        return await BikeFixtureRoads().roadRoute(from: from, to: to, transport: transport)
    }
}
