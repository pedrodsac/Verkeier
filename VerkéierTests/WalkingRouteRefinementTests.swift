import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Walking route refinement")
@MainActor
struct WalkingRouteRefinementTests {
    @Test("Adjacent walks are replaced by one new pedestrian route")
    func adjacentWalksUseDirectPedestrianRoute() async throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let origin = LocationPoint(name: "Héienhaff", latitude: 49.60, longitude: 6.20)
        let alight = LocationPoint(name: "Charlys Statioun", latitude: 49.61, longitude: 6.21)
        let intermediate = LocationPoint(name: "Kapell", latitude: 49.62, longitude: 6.22)
        let destination = LocationPoint(name: "Piste Cyclable", latitude: 49.63, longitude: 6.23)
        let ride = RoutePlan.Leg(
            id: "ride", mode: .bus, transportKind: .transit,
            origin: origin, destination: alight,
            departureTime: start, arrivalTime: start.addingTimeInterval(120),
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(alight)]
        )
        let firstWalk = RoutePlan.Leg(
            id: "first-walk", mode: .walking, transportKind: .walking,
            origin: alight, destination: intermediate,
            departureTime: start.addingTimeInterval(120),
            arrivalTime: start.addingTimeInterval(180), distanceMeters: 65,
            roadRoutingHint: .walking
        )
        let secondWalk = RoutePlan.Leg(
            id: "second-walk", mode: .walking, transportKind: .walking,
            origin: intermediate, destination: destination,
            departureTime: start.addingTimeInterval(180),
            arrivalTime: start.addingTimeInterval(720), distanceMeters: 636,
            roadRoutingHint: .walking
        )
        let option = RouteOption(id: "route", plan: RoutePlan(
            id: "route", origin: origin, destination: destination,
            expectedTravelTime: 720, distanceMeters: 701,
            legs: [ride, firstWalk, secondWalk], dataSource: .local
        ), mapOverlay: nil)
        let directShape = [
            RouteMapCoordinate(alight),
            RouteMapCoordinate(latitude: 49.615, longitude: 6.225),
            RouteMapCoordinate(destination),
        ]
        let probe = RoadRouteRequestProbe()
        let service = MobiliteitRouteService(roadRouteProvider: RecordingRoadRouteProvider(
            probe: probe,
            route: RoadRoute(coordinates: directShape, distanceMeters: 500, expectedTravelTime: 420)
        ))

        let refined = try #require(await service.refineWalkingRoutes(in: [option]).first)
        let calls = await probe.requests
        #expect(calls.count == 1)
        #expect(calls.first?.origin == alight)
        #expect(calls.first?.destination == destination)
        #expect(refined.plan.legs.count == 2)
        let walk = refined.plan.legs[1]
        #expect(walk.id == firstWalk.id)
        #expect(walk.origin == alight)
        #expect(walk.destination == destination)
        #expect(walk.distanceMeters == 500)
        #expect(walk.mapCoordinates == directShape)
        #expect(walk.arrivalTime == start.addingTimeInterval(540))
        #expect(refined.plan.expectedTravelTime == 540)
        #expect(refined.plan.distanceMeters == 500)
        #expect(refined.mapOverlay?.segments.last?.coordinates == directShape)
        #expect(RouteTimelineBuilder.items(from: refined.plan.legs).count == 5)

        let laterTransitShape = [RouteMapCoordinate(origin),
                                 RouteMapCoordinate(latitude: 49.605, longitude: 6.205),
                                 RouteMapCoordinate(alight)]
        let laterTransit = option.replacingLegs([
            RoutePlan.Leg(
                id: "ride", mode: .bus, transportKind: .transit,
                origin: origin, destination: alight,
                departureTime: start, arrivalTime: start.addingTimeInterval(120),
                mapCoordinates: laterTransitShape
            ),
            firstWalk, secondWalk,
        ])
        let preserved = laterTransit.replacingLegs(
            of: .walking, from: refined, preserveUpdatedTotals: true
        )
        #expect(preserved.plan.legs.count == 2)
        #expect(preserved.plan.legs[0].mapCoordinates == laterTransitShape)
        #expect(preserved.plan.legs[1].mapCoordinates == directShape)
    }

    @Test("An estimated straight line does not replace two walks")
    func estimatedDirectWalkDoesNotCollapseLegs() async throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let origin = LocationPoint(latitude: 49.60, longitude: 6.20)
        let middle = LocationPoint(latitude: 49.61, longitude: 6.21)
        let destination = LocationPoint(latitude: 49.62, longitude: 6.22)
        let first = RoutePlan.Leg(
            id: "first", mode: .walking, transportKind: .walking,
            origin: origin, destination: middle,
            departureTime: start, arrivalTime: start.addingTimeInterval(60)
        )
        let second = RoutePlan.Leg(
            id: "second", mode: .walking, transportKind: .walking,
            origin: middle, destination: destination,
            departureTime: start.addingTimeInterval(60),
            arrivalTime: start.addingTimeInterval(600)
        )
        let option = RouteOption(id: "walk", plan: RoutePlan(
            id: "walk", origin: origin, destination: destination,
            expectedTravelTime: 600, distanceMeters: 701,
            legs: [first, second], dataSource: .local
        ), mapOverlay: nil)
        let service = MobiliteitRouteService(roadRouteProvider: FixedRoadRouteProvider(
            route: RoadRoute(
                coordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
                distanceMeters: 500, expectedTravelTime: 420, walkingEvidence: .estimate
            )
        ))

        let refined = try #require(await service.refineWalkingRoutes(in: [option]).first)
        #expect(refined.plan.legs.count == 2)
        #expect(refined.plan.legs.map(\.id) == ["first", "second"])
    }

    @Test("MapKit route data replaces the walking estimate and keeps boarding fixed")
    func mapKitRouteReplacesWalkingEstimate() async throws {
        let boarding = Date(timeIntervalSince1970: 10_000)
        let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
        let stop = LocationPoint(name: "Stop", latitude: 49.62, longitude: 6.13)
        let destination = LocationPoint(name: "Destination", latitude: 49.63, longitude: 6.14)
        let walkingLeg = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: stop,
            departureTime: boarding.addingTimeInterval(-600),
            arrivalTime: boarding,
            distanceMeters: 750,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(stop)],
            roadRoutingHint: .walking
        )
        let transitLeg = RoutePlan.Leg(
            id: "ride",
            mode: .bus,
            transportKind: .transit,
            origin: stop,
            destination: destination,
            departureTime: boarding,
            arrivalTime: boarding.addingTimeInterval(1_200)
        )
        let option = RouteOption(
            id: "route",
            plan: RoutePlan(
                id: "route",
                origin: origin,
                destination: destination,
                expectedTravelTime: 1_800,
                distanceMeters: 750,
                legs: [walkingLeg, transitLeg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
        let mapKitCoordinates = [
            RouteMapCoordinate(origin),
            RouteMapCoordinate(latitude: 49.615, longitude: 6.125),
            RouteMapCoordinate(stop),
        ]
        let service = MobiliteitRouteService(
            roadRouteProvider: FixedRoadRouteProvider(route: RoadRoute(
                coordinates: mapKitCoordinates,
                distanceMeters: 1_100,
                expectedTravelTime: 900
            ))
        )

        let refined = try #require(await service.refineWalkingRoutes(in: [option]).first)
        let walk = try #require(refined.plan.legs.first)

        #expect(walk.mapCoordinates == mapKitCoordinates)
        #expect(walk.distanceMeters == 1_100)
        #expect(walk.arrivalTime == boarding)
        #expect(walk.departureTime == boarding.addingTimeInterval(-900))
        #expect(refined.plan.expectedTravelTime == 2_100)
        #expect(refined.plan.distanceMeters == 1_100)
    }

    @Test("Walking refinements are emitted as each road route completes")
    func walkingRouteUpdatesAreProgressive() async throws {
        let probe = ProgressiveRoadRouteProbe()
        let fastOrigin = LocationPoint(name: "Fast origin", latitude: 49.61, longitude: 6.12)
        let fastDestination = LocationPoint(name: "Fast destination", latitude: 49.615, longitude: 6.125)
        let slowOrigin = LocationPoint(name: "Slow origin", latitude: 49.62, longitude: 6.13)
        let slowDestination = LocationPoint(name: "Slow destination", latitude: 49.625, longitude: 6.135)
        let options = [
            walkingOption(
                id: "fast",
                origin: fastOrigin,
                destination: fastDestination,
                distance: 500,
                duration: 300
            ),
            walkingOption(
                id: "slow",
                origin: slowOrigin,
                destination: slowDestination,
                distance: 700,
                duration: 420
            ),
        ]
        let service = MobiliteitRouteService(
            roadRouteProvider: DelayedRoadRouteProvider(probe: probe)
        )

        var updates: [RouteOption] = []
        var slowRequestHadCompletedBeforeFirstUpdate = false
        for await option in service.refineWalkingRouteUpdates(in: options) {
            if updates.isEmpty {
                slowRequestHadCompletedBeforeFirstUpdate = await probe.didCompleteSlowRequest
            }
            updates.append(option)
        }

        let first = try #require(updates.first)
        #expect(first.id == "fast")
        #expect(!slowRequestHadCompletedBeforeFirstUpdate)
        #expect(first.plan.legs.first?.distanceMeters == 900)
        #expect(updates.count == 2)
    }

    @Test("Transit shapes and walking refinements survive either update order")
    func independentGeometryUpdatesCombine() throws {
        let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
        let stop = LocationPoint(name: "Stop", latitude: 49.615, longitude: 6.125)
        let destination = LocationPoint(name: "Destination", latitude: 49.63, longitude: 6.14)
        let walk = RoutePlan.Leg(
            id: "walk", mode: .walking, transportKind: .walking,
            origin: origin, destination: stop, distanceMeters: 500,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(stop)],
            roadRoutingHint: .walking
        )
        let ride = RoutePlan.Leg(
            id: "ride", mode: .bus, transportKind: .transit,
            origin: stop, destination: destination
        )
        let initial = RouteOption(
            id: "route",
            plan: RoutePlan(
                id: "route", origin: origin, destination: destination,
                expectedTravelTime: 1_500, distanceMeters: 500,
                legs: [walk, ride], dataSource: .local
            ),
            mapOverlay: nil
        )
        let walkingShape = [
            RouteMapCoordinate(origin),
            RouteMapCoordinate(latitude: 49.612, longitude: 6.123),
            RouteMapCoordinate(stop),
        ]
        let busShape = [
            RouteMapCoordinate(stop),
            RouteMapCoordinate(latitude: 49.62, longitude: 6.13),
            RouteMapCoordinate(destination),
        ]
        let walkingUpdate = initial.replacingLegs(
            [RoutePlan.Leg(
                id: "walk", mode: .walking, transportKind: .walking,
                origin: origin, destination: stop, distanceMeters: 700,
                mapCoordinates: walkingShape, roadRoutingHint: .walking
            ), ride],
            expectedTravelTime: 1_650,
            distanceMeters: 700
        )
        let transitUpdate = initial.replacingLegs([
            walk,
            RoutePlan.Leg(
                id: "ride", mode: .bus, transportKind: .transit,
                origin: stop, destination: destination,
                mapCoordinates: busShape
            ),
        ])

        let walkingLast = walkingUpdate.replacingLegs(of: .transit, from: transitUpdate)
        let transitLast = transitUpdate.replacingLegs(
            of: .walking, from: walkingUpdate, preserveUpdatedTotals: true
        )
        for result in [walkingLast, transitLast] {
            #expect(result.plan.legs[0].mapCoordinates == walkingShape)
            #expect(result.plan.legs[1].mapCoordinates == busShape)
            #expect(result.mapOverlay?.segments.count == 2)
            #expect(result.plan.expectedTravelTime == 1_650)
            #expect(result.plan.distanceMeters == 700)
        }
    }

    @Test("Walking refinement starts before progressive route updates finish")
    func refinementStartsWithFirstVisibleUpdate() async throws {
        let probe = RefinementProbe()
        let service = StreamingRefiningRouteService(probe: probe)
        let viewModel = TransitMapViewModel()
        viewModel.routeOrigin = RoutePlace(
            title: "Origin",
            location: service.origin,
            source: .search
        )
        viewModel.routeDestination = RoutePlace(
            title: "Destination",
            location: service.destination,
            source: .search
        )

        let routeTask = Task {
            await viewModel.calculateRoute(using: service, from: nil)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await !probe.didStart, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await probe.didStart)
        #expect(!viewModel.routeOptions.isEmpty)
        #expect(await !probe.didFinishRouteStream)

        routeTask.cancel()
        await routeTask.value
    }

    @Test("Longer transfer walk uses waiting without changing door-to-door time")
    func transferWalkUsesWaitingTime() async throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let option = transferOption(start: start, outgoingOffset: 1_200)
        let refined = try #require(await refinementService(duration: 360)
            .refineWalkingRoutes(in: [option]).first)
        let walk = refined.plan.legs[1]
        #expect(walk.departureTime == start.addingTimeInterval(600))
        #expect(walk.arrivalTime == start.addingTimeInterval(960))
        #expect(refined.plan.expectedTravelTime == 2_400)
        #expect(RouteItineraryValidator.assess(refined, context: .init(
            anchor: start, arriveBy: false, minimumTransferSeconds: 120
        )) == .feasible(minimumTransferSlack: 120))
    }

    @Test("Estimated transfer walking cannot prove a connection feasible")
    func estimatedTransferWalkIsInvalid() {
        let start = Date(timeIntervalSince1970: 100_000)
        let option = transferOption(start: start, outgoingOffset: 1_200,
                                    walkingEvidence: .estimate)
        #expect(RouteItineraryValidator.assess(option, context: .init(
            anchor: start, arriveBy: false, minimumTransferSeconds: 120
        )) == .invalid(.unverifiedTransferWalk))
    }

    @Test("A short same-stop connection stays visible with its published transfer risk")
    func sameStopTransferShortfallIsAtRisk() {
        let start = Date(timeIntervalSince1970: 100_000)
        let origin = LocationPoint(id: "origin", name: "Origin", latitude: 49.60,
                                   longitude: 6.10, transitStopID: "origin")
        let transfer = LocationPoint(id: "transfer", name: "Transfer", latitude: 49.61,
                                     longitude: 6.11, transitStopID: "transfer")
        let destination = LocationPoint(id: "destination", name: "Destination", latitude: 49.62,
                                        longitude: 6.12, transitStopID: "destination")
        let incoming = RoutePlan.Leg(id: "321", mode: .bus, transportKind: .transit,
                                     originStopId: "origin", destinationStopId: "transfer",
                                     origin: origin, destination: transfer,
                                     departureTime: start, arrivalTime: start.addingTimeInterval(600))
        var outgoing = RoutePlan.Leg(id: "25", mode: .bus, transportKind: .transit,
                                     originStopId: "transfer", destinationStopId: "destination",
                                     origin: transfer, destination: destination,
                                     departureTime: start.addingTimeInterval(705),
                                     arrivalTime: start.addingTimeInterval(1_400),
                                     transferWarning: "Tight transfer")
        outgoing.requiredTransferSeconds = 270
        var option = RouteOption(id: "321-25", plan: RoutePlan(
            id: "321-25", origin: origin, destination: destination,
            expectedTravelTime: 1_400, distanceMeters: nil,
            legs: [incoming, outgoing], dataSource: .local
        ), mapOverlay: nil)
        let strict = RouteValidationContext(anchor: start, arriveBy: false,
                                            minimumTransferSeconds: 120)
        #expect(RouteItineraryValidator.assess(option, context: strict) == .invalid(.missedTransfer))
        let tolerant = RouteValidationContext(anchor: start, arriveBy: false,
                                              minimumTransferSeconds: 120,
                                              sameStopTransferShortfallSeconds: 180)
        let assessment = RouteItineraryValidator.assess(option, context: tolerant)
        #expect(assessment == .atRisk(minimumTransferSlack: -165))
        option.feasibility = assessment
        #expect(option.status(at: start) == .atRisk)
        #expect(RouteTimelineBuilder.items(from: option.plan.legs).contains { item in
            if case let .place(node) = item {
                return node.transferWarning == "Tight transfer"
            }
            return false
        })
    }

    @Test("A transfer walk that overlaps the outgoing ride is invalidated")
    func missedTransferIsInvalid() async throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let option = transferOption(start: start, outgoingOffset: 900)
        let service = refinementService(duration: 360)
        let context = RouteValidationContext(anchor: start, arriveBy: false,
                                             minimumTransferSeconds: 120)
        var events: [WalkingRefinementEvent] = []
        for await event in service.refinementEvents(in: [option], context: context) {
            events.append(event)
        }
        #expect(events.count == 1)
        if case let .invalidated(id)? = events.first { #expect(id == option.id) }
        else { Issue.record("Expected an invalidation") }
    }

    @Test("Refined access cannot precede the original departure request")
    func accessBeforeAnchorIsInvalid() async throws {
        let boarding = Date(timeIntervalSince1970: 100_600)
        let origin = LocationPoint(latitude: 49.60, longitude: 6.10)
        let stop = LocationPoint(latitude: 49.61, longitude: 6.11)
        let destination = LocationPoint(latitude: 49.62, longitude: 6.12)
        let walk = RoutePlan.Leg(id: "access", mode: .walking, transportKind: .walking,
                                 origin: origin, destination: stop,
                                 departureTime: boarding.addingTimeInterval(-600),
                                 arrivalTime: boarding, roadRoutingHint: .walking)
        let ride = RoutePlan.Leg(id: "ride", mode: .bus, transportKind: .transit,
                                 origin: stop, destination: destination,
                                 departureTime: boarding,
                                 arrivalTime: boarding.addingTimeInterval(1_200))
        let option = RouteOption(id: "access-option", plan: RoutePlan(
            id: "access-option", origin: origin, destination: destination,
            expectedTravelTime: 1_800, distanceMeters: 600,
            legs: [walk, ride], dataSource: .local
        ), mapOverlay: nil)
        let refined = try #require(await refinementService(duration: 900)
            .refineWalkingRoutes(in: [option]).first)
        #expect(RouteItineraryValidator.assess(refined, context: .init(
            anchor: boarding.addingTimeInterval(-600), arriveBy: false,
            minimumTransferSeconds: 120
        )) == .invalid(.departureBeforeAnchor))
    }

    @Test("Refined egress cannot cross an arrival deadline")
    func egressAfterDeadlineIsInvalid() async throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let origin = LocationPoint(latitude: 49.60, longitude: 6.10)
        let stop = LocationPoint(latitude: 49.61, longitude: 6.11)
        let destination = LocationPoint(latitude: 49.62, longitude: 6.12)
        let ride = RoutePlan.Leg(id: "ride", mode: .bus, transportKind: .transit,
                                 origin: origin, destination: stop,
                                 departureTime: start, arrivalTime: start.addingTimeInterval(600))
        let walk = RoutePlan.Leg(id: "egress", mode: .walking, transportKind: .walking,
                                 origin: stop, destination: destination,
                                 departureTime: start.addingTimeInterval(600),
                                 arrivalTime: start.addingTimeInterval(900),
                                 roadRoutingHint: .walking)
        let option = RouteOption(id: "egress-option", plan: RoutePlan(
            id: "egress-option", origin: origin, destination: destination,
            expectedTravelTime: 900, distanceMeters: 300,
            legs: [ride, walk], dataSource: .local
        ), mapOverlay: nil)
        let refined = try #require(await refinementService(duration: 900)
            .refineWalkingRoutes(in: [option]).first)
        #expect(RouteItineraryValidator.assess(refined, context: .init(
            anchor: start.addingTimeInterval(1_200), arriveBy: true,
            minimumTransferSeconds: 120
        )) == .invalid(.arrivalAfterDeadline))
    }

    private func refinementService(duration: TimeInterval) -> MobiliteitRouteService {
        MobiliteitRouteService(roadRouteProvider: FixedRoadRouteProvider(route: RoadRoute(
            coordinates: [], distanceMeters: 500, expectedTravelTime: duration
        )))
    }

    private func transferOption(start: Date, outgoingOffset: TimeInterval,
                                walkingEvidence: RouteWalkingEvidence? = nil) -> RouteOption {
        let origin = LocationPoint(latitude: 49.60, longitude: 6.10)
        let first = LocationPoint(latitude: 49.61, longitude: 6.11)
        let second = LocationPoint(latitude: 49.615, longitude: 6.115)
        let destination = LocationPoint(latitude: 49.62, longitude: 6.12)
        let incoming = RoutePlan.Leg(id: "incoming", mode: .bus, transportKind: .transit,
                                     origin: origin, destination: first,
                                     departureTime: start, arrivalTime: start.addingTimeInterval(600))
        var walk = RoutePlan.Leg(id: "transfer", mode: .walking, transportKind: .walking,
                                 origin: first, destination: second,
                                 departureTime: start.addingTimeInterval(600),
                                 arrivalTime: start.addingTimeInterval(720),
                                 roadRoutingHint: .walking)
        walk.walkingEvidence = walkingEvidence
        var outgoing = RoutePlan.Leg(id: "outgoing", mode: .train, transportKind: .transit,
                                     origin: second, destination: destination,
                                     departureTime: start.addingTimeInterval(outgoingOffset),
                                     arrivalTime: start.addingTimeInterval(2_400))
        outgoing.requiredTransferSeconds = 120
        return RouteOption(id: "transfer-option", plan: RoutePlan(
            id: "transfer-option", origin: origin, destination: destination,
            expectedTravelTime: 2_400, distanceMeters: 120,
            legs: [incoming, walk, outgoing], dataSource: .local
        ), mapOverlay: nil)
    }

    private func walkingOption(
        id: String,
        origin: LocationPoint,
        destination: LocationPoint,
        distance: Double,
        duration: TimeInterval
    ) -> RouteOption {
        let leg = RoutePlan.Leg(
            id: "\(id)-walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: Date(timeIntervalSince1970: 10_000),
            arrivalTime: Date(timeIntervalSince1970: 10_000 + duration),
            distanceMeters: distance,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            roadRoutingHint: .walking
        )
        return RouteOption(
            id: id,
            plan: RoutePlan(
                id: id,
                origin: origin,
                destination: destination,
                expectedTravelTime: duration,
                distanceMeters: distance,
                legs: [leg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
    }
}

private actor RoadRouteRequestProbe {
    struct Request: Sendable {
        let origin: LocationPoint
        let destination: LocationPoint
    }

    private(set) var requests: [Request] = []

    func record(from origin: LocationPoint, to destination: LocationPoint) {
        requests.append(Request(origin: origin, destination: destination))
    }
}

private struct RecordingRoadRouteProvider: RoadRouteProviding {
    let probe: RoadRouteRequestProbe
    let route: RoadRoute

    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> RoadRoute? {
        await probe.record(from: origin, to: destination)
        return route
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }
}

private struct FixedRoadRouteProvider: RoadRouteProviding {
    let route: RoadRoute

    nonisolated func roadRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> RoadRoute? {
        route
    }

    nonisolated func roadRouteCoordinates(
        from _: LocationPoint,
        to _: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        route.coordinates
    }
}

private actor ProgressiveRoadRouteProbe {
    private(set) var didCompleteSlowRequest = false

    func markCompleted(isSlow: Bool) {
        if isSlow {
            didCompleteSlowRequest = true
        }
    }
}

private struct DelayedRoadRouteProvider: RoadRouteProviding {
    let probe: ProgressiveRoadRouteProbe

    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> RoadRoute? {
        let isSlow = origin.latitude > 49.615
        try? await Task.sleep(for: isSlow ? .milliseconds(250) : .milliseconds(20))
        await probe.markCompleted(isSlow: isSlow)
        return RoadRoute(
            coordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            distanceMeters: isSlow ? 1_100 : 900,
            expectedTravelTime: isSlow ? 600 : 480
        )
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }
}

private actor RefinementProbe {
    var didStart = false
    var didFinishRouteStream = false

    func markStarted() {
        didStart = true
    }

    func markStreamFinished() {
        didFinishRouteStream = true
    }
}

private struct StreamingRefiningRouteService: RouteService, WalkingRouteRefining {
    let probe: RefinementProbe
    let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
    let destination = LocationPoint(name: "Destination", latitude: 49.62, longitude: 6.13)

    nonisolated func calculateRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) async throws -> RouteCalculation {
        calculation
    }

    nonisolated func routeCalculationUpdates(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(calculation)
                do {
                    try await Task.sleep(for: .seconds(5))
                    await probe.markStreamFinished()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    nonisolated func refineWalkingRoutes(in options: [RouteOption]) async -> [RouteOption] {
        await probe.markStarted()
        return options
    }

    @MainActor func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}

    private nonisolated var calculation: RouteCalculation {
        let departure = Date(timeIntervalSince1970: 10_000)
        let leg = RoutePlan.Leg(
            id: "walk",
            mode: .walking,
            transportKind: .walking,
            origin: origin,
            destination: destination,
            departureTime: departure,
            arrivalTime: departure.addingTimeInterval(600),
            distanceMeters: 750,
            mapCoordinates: [RouteMapCoordinate(origin), RouteMapCoordinate(destination)],
            roadRoutingHint: .walking
        )
        let option = RouteOption(
            id: "walk-route",
            plan: RoutePlan(
                id: "walk-route",
                origin: origin,
                destination: destination,
                expectedTravelTime: 600,
                distanceMeters: 750,
                legs: [leg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
        return RouteCalculation(options: [option], selectedOptionID: option.id)
    }
}
