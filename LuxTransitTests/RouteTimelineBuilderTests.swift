import Foundation
import Testing
@testable import LuxTransit

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
        platform: String? = nil,
        delay: Int? = nil,
        status: RouteLegLiveStatus = .scheduled
    ) -> RoutePlan.Leg {
        RoutePlan.Leg(
            id: id,
            mode: mode,
            transportKind: .transit,
            routeName: line,
            origin: point(from),
            destination: point(to),
            departureTime: Date(timeIntervalSince1970: 100),
            arrivalTime: Date(timeIntervalSince1970: 900),
            platform: platform,
            delayMinutes: delay,
            liveStatus: status
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
        #expect(places[1].time == Date(timeIntervalSince1970: 100)) // boarding (departure) time

        // The final place has no outgoing leg: arrival time, no badge.
        #expect(places.last?.showsDelayBadge == false)
        #expect(places.last?.time == Date(timeIntervalSince1970: 900))
    }
}
