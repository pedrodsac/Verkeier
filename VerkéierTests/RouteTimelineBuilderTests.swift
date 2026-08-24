import Foundation
import Testing
@testable import Verkeier

struct RouteTimelineBuilderTests {

    // MARK: - Fixtures

    private func point(_ id: String) -> LocationPoint {
        LocationPoint(id: id, name: id.capitalized, latitude: 0, longitude: 0)
    }

    private func walk(_ id: String, from: String, to: String, minutes: Int = 4, distance: Double = 320) -> RoutePlan
        .Leg {
        RoutePlan.Leg(
            id: id,
            mode: .walking,
            transportKind: .walking,
            origin: point(from),
            destination: point(to),
            departureTime: Date(timeIntervalSince1970: 0),
            arrivalTime: Date(timeIntervalSince1970: Double(minutes) * 60),
            distanceMeters: distance
        )
    }

    private func transit(
        _ id: String,
        from: String,
        to: String,
        line: String = "T1",
        mode: TransportMode = .tram,
        headsign: String? = nil,
        platform: String? = nil,
        delay: Int? = nil,
        status: RouteLegLiveStatus = .scheduled,
        transferWarning: String? = nil,
        stopCount: Int? = nil,
        departure: Double = 100,
        arrival: Double = 900
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: mode,
            transportKind: .transit,
            routeName: line,
            headsign: headsign,
            stopCount: stopCount,
            origin: point(from),
            destination: point(to),
            departureTime: Date(timeIntervalSince1970: departure),
            arrivalTime: Date(timeIntervalSince1970: arrival),
            platform: platform,
            delayMinutes: delay,
            liveStatus: status,
            transferWarning: transferWarning
        )
    }

    // MARK: - Tests

    @Test func emptyLegsProduceNoItems() {
        #expect(RouteTimelineBuilder.items(from: []).isEmpty)
    }

    @Test func interleavesPlacesAndSegments() {
        let legs = [
            walk("w1", from: "origin", to: "hamilius"),
            transit("t1", from: "hamilius", to: "kirchberg"),
            walk("w2", from: "kirchberg", to: "dest")
        ]
        let items = RouteTimelineBuilder.items(from: legs)

        // N legs -> N+1 places + N segments, alternating place/segment/.../place.
        #expect(items.count == legs.count * 2 + 1)

        let places = items.compactMap { if case let .place(p) = $0 { p } else { nil } }
        let segments = items.compactMap { if case let .segment(s) = $0 { s } else { nil } }
        #expect(places.count == legs.count + 1)
        #expect(segments.count == legs.count)

        // Even indices are places, odd are segments.
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 2) {
                #expect({ if case .place = item { true } else { false } }())
            } else {
                #expect({ if case .segment = item { true } else { false } }())
            }
        }
    }

    @Test func walkBetweenTransitsIsTransfer() {
        let legs = [
            transit("t1", from: "a", to: "b"),
            walk("w", from: "b", to: "b2", minutes: 5),
            transit("t2", from: "b2", to: "c", line: "16", mode: .bus)
        ]
        let segments = RouteTimelineBuilder.items(from: legs).compactMap {
            if case let .segment(s) = $0 { s } else { nil }
        }
        #expect(segments.map(\.kind) == [.transit, .transfer, .transit])
    }

    @Test func leadingAndTrailingWalksAreWalkNotTransfer() {
        let legs = [
            walk("w1", from: "origin", to: "stop"),
            transit("t1", from: "stop", to: "dest"),
            walk("w2", from: "dest", to: "door")
        ]
        let segments = RouteTimelineBuilder.items(from: legs).compactMap {
            if case let .segment(s) = $0 { s } else { nil }
        }
        #expect(segments.map(\.kind) == [.walk, .transit, .walk])
    }

    @Test func railEndpointsAreOpen() {
        let legs = [
            walk("w1", from: "origin", to: "stop"),
            transit("t1", from: "stop", to: "dest")
        ]
        let places = RouteTimelineBuilder.items(from: legs).compactMap {
            if case let .place(p) = $0 { p } else { nil }
        }
        #expect(places.first?.railAbove == nil)
        #expect(places.last?.railBelow == nil)
    }

    @Test func transitRailIsSolidWalkRailIsDashed() {
        let legs = [walk("w1", from: "a", to: "b"), transit("t1", from: "b", to: "c", mode: .bus)]
        let segments = RouteTimelineBuilder.items(from: legs).compactMap {
            if case let .segment(s) = $0 { s } else { nil }
        }
        #expect(segments[0].rail == .walk)
        #expect(segments[1].rail == .transit(.bus))
    }

    @Test func transitSegmentsCarryStopCount() {
        let segment = segments([
            transit("t1", from: "a", to: "b", stopCount: 3)
        ]).first

        #expect(segment?.stopCount == 3)
    }

    @Test func boardingPlaceCarriesOutgoingPlatformAndDelay() {
        let legs = [
            walk("w1", from: "origin", to: "stop"),
            transit("t1", from: "stop", to: "dest", platform: "2", delay: 3, status: .delayed)
        ]
        let places = RouteTimelineBuilder.items(from: legs).compactMap {
            if case let .place(p) = $0 { p } else { nil }
        }
        // places[1] is the boarding stop: it owns the outgoing transit leg's data.
        #expect(places[1].platform == "2")
        #expect(places[1].delayMinutes == 3)
        #expect(places[1].showsDelayBadge)
        #expect(places[1].departureTime == Date(timeIntervalSince1970: 100)) // boarding (departure) time

        // The final place has no outgoing leg: arrival time, no badge.
        #expect(places.last?.showsDelayBadge == false)
        #expect(places.last?.arrivalTime == Date(timeIntervalSince1970: 900))
    }

    // MARK: - Roles

    private func places(_ legs: [RoutePlan.Leg]) -> [PlaceNode] {
        RouteTimelineBuilder.items(from: legs).compactMap { if case let .place(p) = $0 { p } else { nil } }
    }

    private func segments(_ legs: [RoutePlan.Leg]) -> [SegmentNode] {
        RouteTimelineBuilder.items(from: legs).compactMap { if case let .segment(s) = $0 { s } else { nil } }
    }

    @Test func rolesFollowJourneyPositionAndMode() {
        // walk → ride → walk: origin, board, alight, destination.
        let roles = places([
            walk("w1", from: "origin", to: "stop"),
            transit("t1", from: "stop", to: "dest"),
            walk("w2", from: "dest", to: "door")
        ]).map(\.role)
        #expect(roles == [.origin, .board, .alight, .destination])
    }

    @Test func directRideToRideIsATransfer() {
        // ride → ride at the same stop: origin, transfer, destination.
        let roles = places([
            transit("t1", from: "a", to: "b"),
            transit("t2", from: "b", to: "c", line: "16", mode: .bus)
        ]).map(\.role)
        #expect(roles == [.origin, .transfer, .destination])
    }

    @Test func walkConnectedTransferSplitsIntoAlightAndBoard() {
        let roles = places([
            transit("t1", from: "a", to: "b"),
            walk("w", from: "b", to: "b2", minutes: 3),
            transit("t2", from: "b2", to: "c", line: "16", mode: .bus)
        ]).map(\.role)
        #expect(roles == [.origin, .alight, .board, .destination])
    }

    // MARK: - Transfer arrival / departure / wait

    @Test func transferPlaceCarriesArrivalDepartureAndWait() {
        let legs = [
            transit("t1", from: "a", to: "b", departure: 0, arrival: 900), // arrives 15:15 → t+900
            transit("t2", from: "b", to: "c", line: "16", mode: .bus, departure: 1200, arrival: 2000)
        ]
        let transferPlace = places(legs)[1]
        #expect(transferPlace.role == .transfer)
        #expect(transferPlace.arrivalTime == Date(timeIntervalSince1970: 900))
        #expect(transferPlace.departureTime == Date(timeIntervalSince1970: 1200))
        #expect(transferPlace.waitMinutes == 5) // (1200 - 900) / 60
    }

    @Test func noWaitWhenArrivalAndDepartureCoincide() {
        let legs = [
            transit("t1", from: "a", to: "b", departure: 0, arrival: 900),
            transit("t2", from: "b", to: "c", line: "16", mode: .bus, departure: 900, arrival: 1500)
        ]
        #expect(places(legs)[1].waitMinutes == nil)
    }

    // MARK: - Tight-transfer warning relocation

    @Test func tightTransferWarningLandsOnTheBoardingPlace() {
        let legs = [
            transit("t1", from: "a", to: "b", departure: 0, arrival: 900),
            transit(
                "t2", from: "b", to: "c", line: "16", mode: .bus,
                transferWarning: "Only 1 min to change", departure: 1000, arrival: 1600
            )
        ]
        let allPlaces = places(legs)
        #expect(allPlaces[0].transferWarning == nil) // origin never warns
        #expect(allPlaces[1].transferWarning == "Only 1 min to change") // the transfer where t2 is boarded
        #expect(allPlaces[2].transferWarning == nil) // destination
    }

    // MARK: - Headsign (no destination fallback)

    @Test func headsignIsPassedThroughButNeverFallsBackToStopName() {
        let withHeadsign = segments([transit("t1", from: "a", to: "b", headsign: "Luxexpo")])[0]
        #expect(withHeadsign.headsign == "Luxexpo")

        // No headsign in the feed ⇒ nil, not the alighting stop's name.
        let withoutHeadsign = segments([transit("t2", from: "a", to: "b")])[0]
        #expect(withoutHeadsign.headsign == nil)
    }

    // MARK: - Id stability (per-leg alert wiring depends on these)

    @Test func itemIdsAreStablePlaceAndSegmentIndices() {
        let legs = [
            walk("w1", from: "origin", to: "stop"),
            transit("t1", from: "stop", to: "dest")
        ]
        let ids = RouteTimelineBuilder.items(from: legs).map(\.id)
        #expect(ids == ["place-0", "segment-0", "place-1", "segment-1", "place-2"])
    }
}
