import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Pafendall funicular connection")
struct PafendallFunicularTests {
    private let tram = LocationPoint(name: "Rout Bréck-Pafendall", latitude: 49.618697, longitude: 6.136686)
    private let train = LocationPoint(name: "Pfaffenthal-Kirchberg", latitude: 49.618936, longitude: 6.132919)

    @Test(arguments: [false, true])
    func routesBothDirectionsWithMeasuredAccess(reverse: Bool) async throws {
        let from = reverse ? train : tram
        let to = reverse ? tram : train
        let router = FunicularPedestrianFixture()
        let route = try #require(await PafendallFunicularConnection.route(from: from, to: to) {
            try await router.route(from: $0, to: $1)
        })
        #expect(route.source == .stationConnection)
        #expect(route.segments.map(\.mode) == [.walking, .funicular, .walking])
        #expect(route.duration == 323) // Two measured 100s walks + 63s ride + 60s boarding.
        let ride = route.segments[1]
        #expect(ride.durationSeconds == 123)
        #expect(ride.distanceMeters > 220 && ride.distanceMeters < 230)
        #expect(ride.polyline.first?.longitude == (reverse ? 6.1327721 : 6.1358874))
        #expect(ride.polyline.last?.longitude == (reverse ? 6.1358874 : 6.1327721))
        #expect(route.coordinates.first?.latitude == from.latitude)
        #expect(route.coordinates.last?.longitude == to.longitude)
        #expect(route.distanceMeters == route.segments.reduce(0) { $0 + $1.distanceMeters })
    }

    @Test func doesNotShortcutSameLevelOrDistantWalks() async throws {
        let nearby = LocationPoint(latitude: 49.618700, longitude: 6.136600)
        let distant = LocationPoint(latitude: 49.63, longitude: 6.13)
        #expect(PafendallFunicularConnection.terminals(from: tram, to: nearby) == nil)
        #expect(PafendallFunicularConnection.terminals(from: distant, to: train) == nil)
        #expect(PafendallFunicularConnection.terminals(from: train, to: train) == nil)
    }

    @Test func requiresMeasuredPedestrianAccess() async throws {
        let route = try await PafendallFunicularConnection.route(from: tram, to: train) { from, to in
            .init(distanceMeters: 100, duration: 100, coordinates: [], source: .straightLineEstimate)
        }
        #expect(route == nil)
    }

    @Test func presentsRideSeparatelyAndProtectsItFromWalkingRefinement() async throws {
        let router = FunicularPedestrianFixture()
        let route = try #require(await PafendallFunicularConnection.route(from: tram, to: train) {
            try await router.route(from: $0, to: $1)
        })
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var original = RoutePlan.Leg(id: "transfer", mode: .walking, transportKind: .walking,
            origin: tram, destination: train, departureTime: start,
            arrivalTime: start.addingTimeInterval(route.duration), distanceMeters: route.distanceMeters,
            mapCoordinates: route.coordinates, roadRoutingHint: .walking)
        original.walkingEvidence = .routedPedestrian
        original.nativeWalkingRange = 1..<2
        let legs = StationConnectionLegMapper.legs(from: original, segments: route.segments)
        #expect(legs.map(\.mode) == [.walking, .funicular, .walking])
        #expect(legs.map(\.transportKind) == [.walking, .transit, .walking])
        #expect(legs[1].routeName == "Funicular")
        #expect(legs[1].tripId == nil) // Continuous station link, without an invented GTFS trip.
        #expect(legs[1].mapCoordinates.count == 9)
        #expect(legs.first?.origin == tram)
        #expect(legs.last?.destination == train)
        #expect(legs.first?.departureTime == start)
        #expect(legs.last?.arrivalTime == original.arrivalTime)
        #expect(legs[0].arrivalTime == legs[1].departureTime)
        #expect(legs[1].arrivalTime == legs[2].departureTime)
        #expect(legs.allSatisfy { $0.nativeWalkingRange == nil })
        #expect(WalkingLegSpan.spans(in: legs).allSatisfy { !$0.needsRouting })
        let encoded = try JSONEncoder().encode(legs)
        #expect(try JSONDecoder().decode([RoutePlan.Leg].self, from: encoded) == legs)
    }

    @Test func providerPreservesSegmentsAndLegacyRefinerDoesNotFlattenRide() async throws {
        let pedestrian = FunicularPedestrianFixture()
        let route = try #require(await PafendallFunicularConnection.route(from: tram, to: train) {
            try await pedestrian.route(from: $0, to: $1)
        })
        let router = ConnectionWalkingFixture(value: route)
        let provider = LocalFirstWalkingRoutingProvider(walkingRouter: router)
        let request = WalkingRequest(source: .init(latitude: tram.latitude, longitude: tram.longitude),
            destination: .init(latitude: train.latitude, longitude: train.longitude))
        let single = try await provider.route(request)
        let batch = await provider.routes([request], maximumConcurrency: 2)
        #expect(single.segments == route.segments)
        let batchRoute = try #require(batch[0])
        #expect(batchRoute.segments == route.segments)
        #expect(single.durationSeconds == 323)
        #expect(try await provider.estimate(request).durationSeconds == single.durationSeconds)
        let roads = LocalFirstRoadRouteProvider(walkingRouter: router)
        #expect(await roads.roadRoute(from: tram, to: train, transport: .walking) == nil)
    }

    @Test func mapsStandardAndExtendedFunicularTypes() {
        #expect(MobiliteitRouteService.mode(forGTFSRouteType: 7) == .funicular)
        #expect(MobiliteitRouteService.mode(forGTFSRouteType: 1400) == .funicular)
    }
}

private nonisolated struct FunicularPedestrianFixture: WalkingRouting {
    func estimates(from: LocationPoint, to: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] { [] }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute {
        .init(distanceMeters: 100, duration: 100,
              coordinates: [.init(latitude: from.latitude, longitude: from.longitude),
                            .init(latitude: to.latitude, longitude: to.longitude)], source: .localOSM)
    }
}

private nonisolated struct ConnectionWalkingFixture: WalkingRouting {
    let value: OfflineWalkingRoute
    func estimates(from: LocationPoint, to destinations: [WalkingDestination]) async throws -> [OfflineWalkingEstimate] {
        destinations.map { .init(destinationID: $0.id, distanceMeters: value.distanceMeters,
                                 duration: value.duration, source: value.source) }
    }
    func route(from: LocationPoint, to: LocationPoint) async throws -> OfflineWalkingRoute { value }
}
