import Foundation
import Testing
@testable import Verkeier

@Suite("Route realtime display overlay")
struct RouteRealtimeEnricherTests {
    @Test("A matching board departure annotates the scheduled route without replanning it")
    func matchingDepartureAddsDelay() async throws {
        let scheduled = Date(timeIntervalSince1970: 2_000_000_000)
        let option = makeOption(scheduled: scheduled)
        let live = Departure(
            id: "live-16",
            stopId: "stop-a",
            routeId: "route-16",
            lineName: "16",
            destination: "Kirchberg, Luxexpo",
            scheduledDeparture: scheduled,
            realtimeDeparture: scheduled.addingTimeInterval(5 * 60),
            delayMinutes: 5,
            platform: "3",
            dataSource: .atpOpenAPI,
            journeyReference: "trip-16"
        )

        let enriched = await RouteRealtimeEnricher(
            liveTransitService: StubRouteLiveTransitService(departures: [live])
        ).enrich([option])

        let result = try #require(enriched.first)
        let leg = try #require(result.transitLegs.first)
        #expect(result.id == option.id)
        #expect(result.plan.legs.map(\.id) == option.plan.legs.map(\.id))
        #expect(leg.scheduledDepartureTime == scheduled)
        #expect(leg.realtimeDepartureTime == scheduled.addingTimeInterval(5 * 60))
        #expect(leg.realtimeArrivalTime == nil)
        #expect(leg.delayMinutes == 5)
        #expect(leg.liveStatus == .delayed)
        #expect(leg.platform == "3")
        #expect(result.status(at: scheduled.addingTimeInterval(-60)) == .delayed)
    }

    @Test("A different service at the same stop cannot annotate the route")
    func unrelatedDepartureIsIgnored() async throws {
        let scheduled = Date(timeIntervalSince1970: 2_000_000_000)
        let option = makeOption(scheduled: scheduled)
        let unrelated = Departure(
            id: "live-18",
            stopId: "stop-a",
            routeId: "route-18",
            lineName: "18",
            destination: "Kirchberg, Luxexpo",
            scheduledDeparture: scheduled,
            realtimeDeparture: scheduled.addingTimeInterval(9 * 60),
            delayMinutes: 9,
            dataSource: .atpOpenAPI
        )

        let enriched = await RouteRealtimeEnricher(
            liveTransitService: StubRouteLiveTransitService(departures: [unrelated])
        ).enrich([option])

        let leg = try #require(enriched.first?.transitLegs.first)
        #expect(leg.realtimeDepartureTime == nil)
        #expect(leg.delayMinutes == nil)
        #expect(leg.liveStatus == .scheduled)
    }

    @Test("A fast live board updates its route without waiting for a slow stop")
    func liveBoardsPublishIncrementally() async {
        let scheduled = Date(timeIntervalSince1970: 2_000_000_000)
        let first = makeOption(scheduled: scheduled)
        let second = makeOption(
            scheduled: scheduled.addingTimeInterval(60),
            optionID: "scheduled-option-2",
            stopID: "stop-b",
            routeID: "route-18",
            lineName: "18",
            tripID: "trip-18"
        )
        let departures = [
            Departure(
                id: "live-16",
                stopId: "stop-a",
                routeId: "route-16",
                lineName: "16",
                destination: "Kirchberg, Luxexpo",
                scheduledDeparture: scheduled,
                realtimeDeparture: scheduled.addingTimeInterval(3 * 60),
                delayMinutes: 3,
                dataSource: .atpOpenAPI,
                journeyReference: "trip-16"
            ),
            Departure(
                id: "live-18",
                stopId: "stop-b",
                routeId: "route-18",
                lineName: "18",
                destination: "Kirchberg, Luxexpo",
                scheduledDeparture: scheduled.addingTimeInterval(60),
                realtimeDeparture: scheduled.addingTimeInterval(5 * 60),
                delayMinutes: 4,
                dataSource: .atpOpenAPI,
                journeyReference: "trip-18"
            ),
        ]
        let enricher = RouteRealtimeEnricher(
            liveTransitService: DelayedRouteLiveTransitService(
                departures: departures,
                delayedStopID: "stop-b"
            )
        )

        var iterator = enricher.updates(for: [first, second]).makeAsyncIterator()
        let started = ContinuousClock.now
        guard let firstUpdate = await iterator.next() else {
            Issue.record("Expected a live update from the fast stop")
            return
        }
        let firstElapsed = started.duration(to: .now)

        #expect(firstElapsed < .milliseconds(250))
        #expect(firstUpdate[0].usesLiveData)
        #expect(!firstUpdate[1].usesLiveData)

        guard let finalUpdate = await iterator.next() else {
            Issue.record("Expected a final update after the slow stop completed")
            return
        }
        let allRoutesUseLiveData = finalUpdate.count == 2
            && finalUpdate[0].usesLiveData
            && finalUpdate[1].usesLiveData
        #expect(allRoutesUseLiveData)
    }

    private func makeOption(
        scheduled: Date,
        optionID: String = "scheduled-option",
        stopID: String = "stop-a",
        routeID: String = "route-16",
        lineName: String = "16",
        tripID: String = "trip-16"
    ) -> RouteOption {
        let origin = LocationPoint(
            id: stopID,
            name: "Gare Centrale",
            latitude: 49.599,
            longitude: 6.134,
            transitStopID: stopID
        )
        let destination = LocationPoint(
            id: "stop-b",
            name: "Luxexpo",
            latitude: 49.632,
            longitude: 6.174,
            transitStopID: "stop-b"
        )
        let leg = RoutePlan.Leg(
            id: "transit-\(tripID)-\(stopID)-stop-destination",
            mode: .bus,
            transportKind: .transit,
            routeName: lineName,
            headsign: "Luxexpo",
            routeId: routeID,
            tripId: tripID,
            originStopId: stopID,
            destinationStopId: "stop-destination",
            origin: origin,
            destination: destination,
            departureTime: scheduled,
            arrivalTime: scheduled.addingTimeInterval(20 * 60),
            scheduledDepartureTime: scheduled,
            scheduledArrivalTime: scheduled.addingTimeInterval(20 * 60)
        )
        return RouteOption(
            id: optionID,
            plan: RoutePlan(
                id: "\(optionID)-plan",
                origin: origin,
                destination: destination,
                expectedTravelTime: 20 * 60,
                distanceMeters: 5_000,
                legs: [leg],
                dataSource: .local
            ),
            mapOverlay: nil
        )
    }
}

private struct DelayedRouteLiveTransitService: LiveTransitService {
    let departures: [Departure]
    let delayedStopID: String
    let isConfigured = true

    func nearbyStops(
        to _: LocationPoint,
        radiusMeters _: Int,
        limit _: Int
    ) async throws -> [LiveTransitStop] {
        []
    }

    func departureBoard(
        for stop: Stop,
        filter _: TransitBoardFilter
    ) async throws -> [Departure] {
        if stop.id == delayedStopID {
            try await Task.sleep(for: .milliseconds(500))
        }
        return departures.filter { $0.stopId == stop.id }
    }
}

private struct StubRouteLiveTransitService: LiveTransitService {
    let departures: [Departure]
    let isConfigured = true

    func nearbyStops(
        to _: LocationPoint,
        radiusMeters _: Int,
        limit _: Int
    ) async throws -> [LiveTransitStop] {
        []
    }

    func departureBoard(
        for _: Stop,
        filter _: TransitBoardFilter
    ) async throws -> [Departure] {
        departures
    }
}
