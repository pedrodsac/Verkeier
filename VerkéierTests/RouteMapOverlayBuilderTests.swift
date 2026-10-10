import Foundation
import Testing
@testable import Verkeier

struct RouteMapOverlayBuilderTests {
    @Test func orderedVisitsPreserveLoopsAndShortNames() {
        let leg = ride("bus", stops: [stop("a"), stop("b"), stop("a")])
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [leg])
        #expect(overlay.stopMarkers.map(\.stopID) == ["a", "b", "a"])
        #expect(Set(overlay.stopMarkers.map(\.id)).count == 3)
        #expect(overlay.stopMarkers.map(\.role) == [.boarding, .intermediate, .alighting])
        #expect(overlay.segments.first?.coordinates == leg.mapCoordinates)
        #expect(overlay.segments.first?.routeShortName == "322")
    }

    @Test func onlyCoincidentAdjacentBoundariesMerge() {
        let first = ride("first", stops: [stop("a"), stop("b")])
        let second = ride("second", stops: [stop("b"), stop("c")])
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [first, second])
        #expect(overlay.stopMarkers.count == 3)
        #expect(overlay.stopMarkers[1].role == .transfer)
        #expect(overlay.stopMarkers[1].segmentIDs == ["first", "second"])
        let walk = RoutePlan.Leg(id: "walk", mode: .walking, transportKind: .walking,
            origin: first.destination, destination: second.origin)
        let separate = RouteMapOverlayBuilder.itinerary(legs: [first, walk, second])
        #expect(separate.stopMarkers.count == 4)
        #expect(separate.stopMarkers.filter { $0.role == .transfer }.count == 2)
    }

    @Test func walkingTransferKeepsBothRealStopLocations() {
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [
            ride("first", stops: [stop("a"), stop("b")]),
            ride("second", stops: [stop("c"), stop("d")])
        ])
        #expect(overlay.stopMarkers.map(\.role) == [.boarding, .transfer, .transfer, .alighting])
        #expect(overlay.stopMarkers[1].coordinate != overlay.stopMarkers[2].coordinate)
    }

    @Test func inSeatContinuationIsNotATransfer() {
        let first = ride("first", stops: [stop("a"), stop("b")])
        var second = ride("second", stops: [stop("b"), stop("c")])
        second.continuesInSeatFromTripID = "first-trip"
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [first, second])
        #expect(overlay.stopMarkers.count == 3)
        #expect(overlay.stopMarkers[1].role == .intermediate)
        #expect(!overlay.stopMarkers.contains { $0.role == .transfer })
    }

    @Test func lineTerminiAndRepeatedStopOccurrencesRemainDistinct() {
        let stops = [stop("a"), stop("b"), stop("a")]
        let overlay = RouteMapOverlayBuilder.line(segment: segment(), stops: stops)
        #expect(overlay.stopMarkers.map(\.role) == [.terminus, .intermediate, .terminus])
        #expect(Set(overlay.stopMarkers.map(\.id)).count == 3)
    }

    @Test func tripBoardingAndAlightingOverrideTermini() throws {
        var leg = ride("ride", stops: [stop("a"), stop("b"), stop("c")])
        leg.tripInstance = .init(feedGeneration: 1, tripID: "trip", serviceDate: "20261010")
        leg.boardingStopSequence = 1
        leg.alightingStopSequence = 2
        let selection = try #require(TripDetailSelection(leg: leg))
        let stops = [stop("a"), stop("b"), stop("c")].enumerated().map { index, value in
            TripStopEntry(sequence: index + 1,
                stop: Stop(id: value.stopID!, name: value.name,
                    location: .init(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude),
                    modes: [.bus], dataSource: .mock), arrival: nil, departure: nil, platform: nil)
        }
        let overlay = RouteMapOverlayBuilder.trip(segments: [segment("full-run"), segment("your-ride")],
            stops: stops, selection: selection)
        #expect(overlay.stopMarkers.map(\.role) == [.boarding, .alighting, .terminus])
        #expect(overlay.stopMarkers.map(\.emphasis) == [.highlighted, .highlighted, .context])
        #expect(overlay.stopMarkers.map(\.segmentIDs) == [["your-ride"], ["your-ride"], ["full-run"]])
        #expect(selection.routeShortName == "322")
    }

    @Test func refinementsKeepStopsAndShieldMetadataInEitherOrder() {
        let leg = ride("ride", stops: [stop("a"), stop("b"), stop("c")])
        let walk = RoutePlan.Leg(id: "walk", mode: .walking, transportKind: .walking,
            origin: leg.destination, destination: .init(latitude: 49.65, longitude: 6.2),
            mapCoordinates: [leg.mapCoordinates.last!, .init(latitude: 49.65, longitude: 6.2)])
        let plan = RoutePlan(id: "plan", origin: leg.origin, destination: walk.destination,
            expectedTravelTime: 500, distanceMeters: 100, legs: [leg, walk], dataSource: .local)
        let original = RouteOption(id: "plan", plan: plan, mapOverlay: RouteMapOverlayBuilder.itinerary(legs: plan.legs))
        let shape = original.replacingLegs([leg, walk])
        let walking = original.replacingLegs([leg, walk], expectedTravelTime: 550)
        for value in [shape.replacingLegs(of: .walking, from: walking), walking.replacingLegs(of: .transit, from: shape)] {
            #expect(value.mapOverlay?.stopMarkers == original.mapOverlay?.stopMarkers)
            #expect(value.mapOverlay?.segments.first?.routeShortName == "322")
        }
    }

    @Test func missingGeometryDoesNotInventAStraightLine() {
        let empty = RoutePlan.Leg(id: "empty", mode: .bus, transportKind: .transit,
            origin: .init(latitude: 49.6, longitude: 6.1), destination: .init(latitude: 49.7, longitude: 6.2))
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [empty])
        #expect(overlay.isEmpty)
        #expect(overlay.stopMarkers.isEmpty)
    }

    @Test func approximateWalkingRetainsEvidence() {
        var leg = ride("walk", stops: [stop("a"), stop("b")])
        leg.walkingEvidence = .estimate
        // Evidence on a transit leg must not misclassify its route shape.
        #expect(RouteMapOverlayBuilder.itinerary(legs: [leg]).segments.first?.isApproximate == nil)
        var walk = RoutePlan.Leg(id: "walk", mode: .walking, transportKind: .walking,
            origin: leg.origin, destination: leg.destination, mapCoordinates: leg.mapCoordinates)
        walk.walkingEvidence = .estimate
        #expect(RouteMapOverlayBuilder.itinerary(legs: [walk]).segments.first?.isApproximate == true)
    }

    @Test func olderCodablePayloadsDecodeWithoutNewMetadata() throws {
        let overlay = RouteMapOverlayBuilder.itinerary(legs: [ride("leg", stops: [stop("a"), stop("b")])])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(overlay)) as? [String: Any])
        json.removeValue(forKey: "stopMarkers")
        var segments = try #require(json["segments"] as? [[String: Any]])
        segments[0].removeValue(forKey: "routeShortName")
        json["segments"] = segments
        let decoded = try JSONDecoder().decode(RouteMapOverlay.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.stopMarkers.isEmpty)
        #expect(decoded.segments.first?.routeShortName == nil)
        var legJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ride("leg", stops: [stop("a"), stop("b")]))) as? [String: Any])
        legJSON.removeValue(forKey: "mapStops")
        legJSON.removeValue(forKey: "routeShortName")
        let oldLeg = try JSONDecoder().decode(RoutePlan.Leg.self, from: JSONSerialization.data(withJSONObject: legJSON))
        #expect(oldLeg.mapStops == nil)
        #expect(oldLeg.routeShortName == nil)
        #expect(try JSONDecoder().decode(RouteMapOverlay.self, from: JSONEncoder().encode(overlay)) == overlay)
    }

    private func stop(_ id: String) -> RouteStopOccurrence {
        .init(id: UUID().uuidString, stopID: id, name: "Stop \(id)",
            coordinate: .init(latitude: 49.6 + Double(id.utf8.first! - 97) * 0.01, longitude: 6.1))
    }

    private func ride(_ id: String, stops: [RouteStopOccurrence]) -> RoutePlan.Leg {
        RoutePlan.Leg(id: id, mode: .bus, transportKind: .transit, routeName: "Long descriptive route name",
            originStopId: stops.first?.stopID, destinationStopId: stops.last?.stopID,
            origin: .init(latitude: stops.first!.coordinate.latitude, longitude: 6.1),
            destination: .init(latitude: stops.last!.coordinate.latitude, longitude: 6.1),
            mapCoordinates: stops.map(\.coordinate), mapStops: stops, routeShortName: "322")
    }

    private func segment(_ id: String = "line") -> RouteMapSegment {
        .init(id: id, mode: .bus, coordinates: [stop("a").coordinate, stop("b").coordinate], routeShortName: "322")
    }
}
