import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Tight transfer card evidence")
struct RouteTightTransferTests {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [-1.0, 0, 119, 119.9, 120, 155, 450])
    func pillUsesEffectiveGapStrictlyBelowTwoMinutes(gap: Double) {
        let route = option(gap: gap)
        #expect(route.hasTightTransfer == (gap >= 0 && gap < 120))
        #expect((route.status(at: anchor) == .atRisk) == (gap >= 0 && gap < 120))
    }

    @Test func staleWarningsAndOtherStatusesDoNotCreateTightPill() {
        for status in [RouteLegLiveStatus.scheduled, .live, .delayed, .cancelled] {
            let route = option(gap: 155, liveStatus: status, warning: "Tight transfer")
            #expect(!route.hasTightTransfer)
        }
    }

    @Test func realtimeTimesOverrideScheduledGapAndContinuationsHaveNoPill() {
        let delayed = option(gap: 155, realtimeArrival: 636)
        #expect(delayed.hasTightTransfer)
        #expect(!option(gap: 155, realtimeArrival: 636, realtimeDeparture: 756).hasTightTransfer)
        #expect(!option(gap: 155, realtimeArrival: 636, realtimeDeparture: 700, continuation: true).hasTightTransfer)
        #expect(!delayed.replacingLegs([delayed.plan.legs[0]]).hasTightTransfer)
        #expect(!option(gap: 155, unknownDeparture: true).hasTightTransfer)
    }

    private func option(gap: Double, realtimeArrival: Double? = nil, realtimeDeparture: Double? = nil,
                        continuation: Bool = false, unknownDeparture: Bool = false,
                        liveStatus: RouteLegLiveStatus = .scheduled, warning: String? = nil) -> RouteOption {
        let point = LocationPoint(latitude: 49.6, longitude: 6.1)
        let legs = [
            RoutePlan.Leg(id: "incoming", mode: .bus, transportKind: .transit,
                origin: point, destination: point, departureTime: anchor.addingTimeInterval(300),
                arrivalTime: anchor.addingTimeInterval(600),
                realtimeArrivalTime: realtimeArrival.map { anchor.addingTimeInterval($0) }),
            RoutePlan.Leg(id: "outgoing", mode: .bus, transportKind: .transit,
                origin: point, destination: point,
                departureTime: unknownDeparture ? nil : anchor.addingTimeInterval(600 + gap),
                arrivalTime: anchor.addingTimeInterval(1_200),
                realtimeDepartureTime: realtimeDeparture.map { anchor.addingTimeInterval($0) },
                liveStatus: liveStatus, transferWarning: warning)
        ]
        var updated = legs
        updated[1].continuesInSeatFromTripID = continuation ? "incoming" : nil
        return RouteOption(id: "route", plan: RoutePlan(id: "plan", origin: point, destination: point,
            expectedTravelTime: 900, distanceMeters: 0, legs: updated, dataSource: .mock), mapOverlay: nil,
            statusEvidence: .init(firstBoarding: anchor.addingTimeInterval(300), cancelled: false,
                delayed: false, tightTransfer: true, coverage: .scheduleOnly))
    }
}
