import Foundation
import Testing
@testable import Verkeier

@Suite("Combined stay-aboard timeline rides")
@MainActor
struct RouteTimelinePresentationTests {
    private let start = Date(timeIntervalSince1970: 100_000)

    private func leg(_ id: String, line: String, headsign: String? = nil,
        departure: TimeInterval, arrival: TimeInterval, stops: Int? = nil,
        continuesFrom: String? = nil, liveArrival: TimeInterval? = nil,
        status: RouteLegLiveStatus = .scheduled) -> RoutePlan.Leg {
        var leg = RoutePlan.Leg(id: id, mode: .bus, transportKind: .transit,
            routeName: line, headsign: headsign, tripId: id, stopCount: stops,
            origin: .init(name: "Origin", latitude: 49.6, longitude: 6.1),
            destination: .init(name: "Destination", latitude: 49.7, longitude: 6.2),
            departureTime: start.addingTimeInterval(departure), arrivalTime: start.addingTimeInterval(arrival),
            realtimeArrivalTime: liveArrival.map { start.addingTimeInterval($0) }, liveStatus: status)
        leg.continuesInSeatFromTripID = continuesFrom
        leg.tripInstance = .init(feedGeneration: 1, tripID: id, serviceDate: "20261010")
        leg.boardingStopSequence = 1
        leg.alightingStopSequence = (stops ?? 1) + 1
        return leg
    }

    @Test func continuationUsesOneChipCaptionAndCombinedTotals() throws {
        let first = leg("first", line: "7", departure: 0, arrival: 120, stops: 1)
        let onward = leg("onward", line: "25", headsign: "Domeldange, Gare routière",
            departure: 150, arrival: 360, stops: 5, continuesFrom: "first")
        let items = RouteTimelinePresentation.items(from: [first, onward])
        #expect(items.map(\.id) == ["place-0", "segment-0", "place-2"])
        guard case let .segment(ride) = items[1] else { Issue.record("Missing combined ride"); return }
        #expect(ride.badgeText == "7")
        #expect(ride.continuationCaptions == ["Continues as 25: Domeldange, Gare routière"])
        #expect(ride.durationMinutes == 6)
        #expect(ride.stopCount == 6)
        #expect(ride.sourceSegmentIDs == ["segment-0", "segment-1"])
        #expect(ride.tripSelection?.continuingRides.map(\.instance.tripID) == ["onward"])
    }

    @Test func multipleContinuationsIncludeDwellAndRealtimeAndKeepTransferSeparate() throws {
        let first = leg("first", line: "7", departure: 0, arrival: 120, stops: 1)
        let second = leg("second", line: "25", departure: 150, arrival: 360, stops: 5, continuesFrom: "first")
        let third = leg("third", line: "30", departure: 420, arrival: 480, stops: 1,
            continuesFrom: "second", liveArrival: 600, status: .cancelled)
        let transfer = leg("transfer", line: "18", departure: 660, arrival: 900, stops: 2)
        let items = RouteTimelinePresentation.items(from: [first, second, third, transfer])
        #expect(items.map(\.id) == ["place-0", "segment-0", "place-3", "segment-3", "place-4"])
        guard case let .segment(ride) = items[1], case let .place(boundary) = items[2] else {
            Issue.record("Missing ride or transfer"); return
        }
        #expect(ride.continuationCaptions == ["Continues as 25", "Continues as 30"])
        #expect(ride.durationMinutes == 10)
        #expect(ride.stopCount == 7)
        #expect(ride.hasCancelledContinuation)
        #expect(boundary.role == .transfer)
    }

    @Test func missingStopCountIsNotPresentedAsCompleteTotal() throws {
        let first = leg("first", line: "7", departure: 0, arrival: 120, stops: 1)
        let onward = leg("onward", line: "25", departure: 120, arrival: 360, continuesFrom: "first")
        let items = RouteTimelinePresentation.items(from: [first, onward])
        guard case let .segment(ride) = items[1] else { Issue.record("Missing ride"); return }
        #expect(ride.stopCount == nil)
        #expect(ride.durationMinutes == 6)
    }

    @Test func ordinaryTransfersKeepBothChipsAndStopNode() {
        let legs = [leg("first", line: "7", departure: 0, arrival: 120, stops: 1),
                    leg("onward", line: "25", departure: 180, arrival: 360, stops: 5)]
        #expect(RouteTimelinePresentation.items(from: legs) == RouteTimelineBuilder.items(from: legs))
    }
}
