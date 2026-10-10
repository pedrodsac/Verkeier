import Foundation
import Testing
@testable import Verkeier

@MainActor
struct MapTransferWalkingTests {
    @Test func pedestrianPathIsOnlyAddedToTheMapAndSharedAcrossAlternatives() async throws {
        let original = option()
        let duplicate = RouteOption(id: "alternative", plan: original.plan, mapOverlay: original.mapOverlay)
        let probe = TransferWalkingProbe()
        let route = path()
        let service = MobiliteitRouteService(roadRouteProvider: TransferWalkingProvider(probe: probe, route: route))
        let updated = await service.addingMapTransferWalks(to: [original, duplicate])

        let requests = await probe.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(RouteMapCoordinate(request.origin) == original.plan.legs[0].mapCoordinates.last)
        #expect(RouteMapCoordinate(request.destination) == original.plan.legs[1].mapCoordinates.first)
        #expect(RouteMapCoordinate(request.origin) != RouteMapCoordinate(original.plan.legs[0].destination))
        for (source, result) in zip([original, duplicate], updated) {
            #expect(result.plan == source.plan)
            #expect(result.transferCount == source.transferCount)
            #expect(result.transferGapDurations == source.transferGapDurations)
            #expect(result.mapOverlay?.stopMarkers == source.mapOverlay?.stopMarkers)
            let walk = try #require(result.mapOverlay?.segments.first { $0.mode == .walking })
            #expect(walk.coordinates == route.coordinates)
            #expect(walk.coordinates.count == 3)
            #expect(walk.isApproximate == false)
            #expect(!result.plan.legs.contains { $0.transportKind == .walking })
        }
    }

    @Test(arguments: [false, true])
    func unavailableOrEstimatedPathsLeaveTheGapDisconnected(estimated: Bool) async {
        let original = option()
        let probe = TransferWalkingProbe()
        let service = MobiliteitRouteService(roadRouteProvider: TransferWalkingProvider(
            probe: probe, route: estimated ? path(evidence: .estimate) : nil))
        let updated = await service.addingMapTransferWalks(to: [original])
        #expect(updated == [original])
    }

    @Test func noMapWalkForAnExplicitWalkOrAnInSeatContinuation() {
        let legs = option().plan.legs
        let explicitWalk = RoutePlan.Leg(id: "walk", mode: .walking, transportKind: .walking,
            origin: legs[0].destination, destination: legs[1].origin)
        #expect(MapTransferWalkingRequest.requests(in: [legs[0], explicitWalk, legs[1]]).isEmpty)
        var continuation = legs[1]
        continuation.continuesInSeatFromTripID = "incoming-trip"
        #expect(MapTransferWalkingRequest.requests(in: [legs[0], continuation]).isEmpty)
        #expect(MapTransferWalkingRequest.requests(in: [legs[0]]).isEmpty)
        #expect(MapTransferWalkingRequest.requests(in: option(departureBay: arrivalBay).plan.legs).isEmpty)
    }

    @Test func refinementsRetainOnlyPathsForTheCurrentShapeEndpoints() throws {
        let original = option()
        let request = try #require(MapTransferWalkingRequest.requests(in: original.plan.legs).first)
        let decorated = original.addingMapTransferWalks(routesByKey: [request.geometry.key: path()])
        let rebuilt = decorated.replacingLegs(decorated.plan.legs)
        #expect(rebuilt.mapOverlay == decorated.mapOverlay)
        #expect(rebuilt.plan == decorated.plan)
        let merged = decorated.replacingLegs(of: .transit, from: original)
        #expect(merged.mapOverlay == decorated.mapOverlay)
        let changed = option(departureBay: .init(latitude: 49.637, longitude: 6.1748))
        let replaced = decorated.replacingLegs(of: .transit, from: changed)
        #expect(replaced.mapOverlay?.segments.contains { $0.mode == .walking } == false)
        let repeated = decorated.addingMapTransferWalks(routesByKey: [request.geometry.key: path()])
        #expect(repeated == decorated)
    }

    private var arrivalBay: RouteMapCoordinate { .init(latitude: 49.636269, longitude: 6.174646) }
    private var departureBay: RouteMapCoordinate { .init(latitude: 49.636666, longitude: 6.175198) }

    private func path(evidence: RouteWalkingEvidence = .routedPedestrian) -> RoadRoute {
        .init(coordinates: [arrivalBay, .init(latitude: 49.63645, longitude: 6.1753), departureBay],
              distanceMeters: 104, expectedTravelTime: 90, walkingEvidence: evidence)
    }

    private func option(departureBay: RouteMapCoordinate? = nil) -> RouteOption {
        let station = LocationPoint(name: "Luxexpo", latitude: 49.636375, longitude: 6.174766)
        let origin = LocationPoint(latitude: 49.65, longitude: 6.2)
        let destination = LocationPoint(latitude: 49.62, longitude: 6.15)
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let legs = [
            RoutePlan.Leg(id: "incoming", mode: .bus, transportKind: .transit, routeName: "326",
                originStopId: "origin", destinationStopId: "station", origin: origin, destination: station,
                departureTime: anchor, arrivalTime: anchor.addingTimeInterval(600),
                mapCoordinates: [RouteMapCoordinate(origin), arrivalBay]),
            RoutePlan.Leg(id: "outgoing", mode: .bus, transportKind: .transit, routeName: "6",
                originStopId: "station", destinationStopId: "destination", origin: station, destination: destination,
                departureTime: anchor.addingTimeInterval(720), arrivalTime: anchor.addingTimeInterval(1_200),
                mapCoordinates: [departureBay ?? self.departureBay, RouteMapCoordinate(destination)])
        ]
        let plan = RoutePlan(id: "journey", origin: origin, destination: destination,
            expectedTravelTime: 1_200, distanceMeters: 385, legs: legs, dataSource: .local)
        return RouteOption(id: plan.id, plan: plan, mapOverlay: RouteMapOverlayBuilder.itinerary(legs: legs))
    }
}

private actor TransferWalkingProbe {
    private(set) var requests: [WalkingGeometryRequest] = []
    func record(from: LocationPoint, to: LocationPoint) {
        requests.append(.init(origin: from, destination: to))
    }
}

private nonisolated struct TransferWalkingProvider: RoadRouteProviding {
    let probe: TransferWalkingProbe
    let route: RoadRoute?
    func roadRoute(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> RoadRoute? {
        #expect(transport == .walking)
        await probe.record(from: from, to: to)
        return route
    }
    func roadRouteCoordinates(from: LocationPoint, to: LocationPoint, transport: RoadRouteTransport) async -> [RouteMapCoordinate]? {
        await roadRoute(from: from, to: to, transport: transport)?.coordinates
    }
}
