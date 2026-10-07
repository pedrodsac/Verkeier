import Foundation
import Testing
@testable import Verkeier

@Suite("Route option time dominance")
@MainActor
struct RouteOptionVisibilityTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Presentation hides the final result after time dominance filtering")
    func hidesFinalFilteredResult() {
        let slow = option("slow", departure: 0, arrival: 1_800)
        let fast = option("fast", departure: 300, arrival: 1_200)
        let later = option("later", departure: 900, arrival: 2_100)
        let visible = RouteOptionVisibility.presentedOptions(
            primary: [slow, fast, later], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [fast.id])
    }

    @Test("Presentation handles empty and single result lists")
    func hidesSingleResult() {
        for options in [[], [option("only", departure: 0, arrival: 1_200)]] {
            let visible = RouteOptionVisibility.presentedOptions(
                primary: options, supplemental: [], at: anchor)
            #expect(visible.primary.isEmpty)
        }
    }

    @Test("Later departures and earlier arrivals hide slower routes, including equal boundaries",
          arguments: [0.0, 300.0], [1_200.0, 1_800.0])
    func hidesDominatedOptions(departure: TimeInterval, arrival: TimeInterval) {
        let slow = option("slow", departure: 0, arrival: 1_800)
        let fast = option("fast", departure: departure, arrival: arrival)
        for options in [[slow, fast], [fast, slow]] {
            let visible = RouteOptionVisibility.visibleOptions(primary: options, supplemental: [], at: anchor)
            let expected = departure == 0 && arrival == 1_800 ? options.map(\.id) : [fast.id]
            #expect(visible.primary.map(\.id) == expected)
        }
    }

    @Test("Earlier arrivals and later departures remain genuine time tradeoffs")
    func preservesTimeTradeoffs() {
        let early = option("early", departure: 0, arrival: 1_200)
        let later = option("later", departure: 600, arrival: 1_800)
        let visible = RouteOptionVisibility.visibleOptions(primary: [early, later], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [early.id, later.id])
    }

    @Test("Only the fastest nested time interval survives")
    func removesDominanceChain() {
        let options = [
            option("slow", departure: 0, arrival: 1_800),
            option("middle", departure: 300, arrival: 1_500),
            option("fast", departure: 600, arrival: 1_200)
        ]
        let visible = RouteOptionVisibility.visibleOptions(primary: options, supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == ["fast"])
    }

    @Test("Fewer transfers do not exempt a slower journey from time dominance")
    func transferBurdenDoesNotKeepSlowerRoute() {
        let slowDirect = option("direct", departure: 0, arrival: 1_800)
        let firstRide = option("firstRide", departure: 300, arrival: 600).plan.legs[0]
        let secondRide = option("secondRide", mode: .tram, departure: 900, arrival: 1_200).plan.legs[0]
        let fast = option("fast", departure: 300, arrival: 1_200).replacingLegs([firstRide, secondRide])
        #expect(fast.transferCount > slowDirect.transferCount)
        let visible = RouteOptionVisibility.visibleOptions(primary: [slowDirect, fast], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [fast.id])
    }

    @Test("Bike alternatives remain a separate choice regardless of transit timing")
    func comparesSupplementalOptions() {
        let slowBus = option("slowBus", departure: 0, arrival: 1_800)
        let fastBike = option("fastBike", mode: .bicycle, departure: 300, arrival: 1_200)
        let bikeWins = RouteOptionVisibility.visibleOptions(primary: [slowBus], supplemental: [fastBike], at: anchor)
        #expect(bikeWins.primary.map(\.id) == [slowBus.id])
        #expect(bikeWins.supplemental.map(\.id) == [fastBike.id])

        let fastBus = option("fastBus", departure: 300, arrival: 1_200)
        let slowBike = option("slowBike", mode: .bicycle, departure: 0, arrival: 1_800)
        let busWins = RouteOptionVisibility.visibleOptions(primary: [fastBus], supplemental: [slowBike], at: anchor)
        #expect(busWins.primary.map(\.id) == [fastBus.id])
        #expect(busWins.supplemental.map(\.id) == [slowBike.id])
    }

    @Test("A walking recommendation keeps the separate bike alternative")
    func walkingRecommendationPreservesBike() {
        let bus = option("bus", departure: 600, arrival: 1_800)
        let walk = option("walk", mode: .walking, departure: 0, arrival: 600)
        let bike = option("bike", mode: .bicycle, departure: 0, arrival: 900)
        let visible = RouteOptionVisibility.visibleOptions(primary: [bus, walk], supplemental: [bike], at: anchor)
        #expect(visible.primary.map(\.id) == [walk.id])
        #expect(visible.supplemental.map(\.id) == [bike.id])
    }

    @Test("Walking that departs later and arrives at the same time hides transit")
    func equalArrivalFavorsLaterWalkingDeparture() {
        let bus = option("bus", departure: 0, arrival: 1_200)
        let walk = option("walk", mode: .walking, departure: 300, arrival: 1_200)
        let visible = RouteOptionVisibility.visibleOptions(primary: [bus, walk], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [walk.id])
    }

    @Test("Realtime departure and arrival predictions determine dominance")
    func usesRealtimeTimes() {
        let slow = option("slow", departure: 300, arrival: 1_500)
        let fast = option("fast", departure: 0, arrival: 1_800,
                          realtimeDeparture: 600, realtimeArrival: 1_200)
        let visible = RouteOptionVisibility.visibleOptions(primary: [slow, fast], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [fast.id])
    }

    @Test("Access and egress walks determine the complete journey interval")
    func usesDoorToDoorTimes() {
        let direct = option("direct", departure: 300, arrival: 1_500)
        let ride = option("ride", departure: 600, arrival: 1_200)
        let access = option("access", mode: .walking, departure: 0, arrival: 600).plan.legs[0]
        let egress = option("egress", mode: .walking, departure: 1_200, arrival: 1_800).plan.legs[0]
        let withAccess = ride.replacingLegs([access, ride.plan.legs[0]])
        let withEgress = ride.replacingLegs([ride.plan.legs[0], egress])
        for alternative in [withAccess, withEgress] {
            let visible = RouteOptionVisibility.visibleOptions(primary: [direct, alternative], supplemental: [], at: anchor)
            #expect(visible.primary.map(\.id) == [direct.id, alternative.id])
        }
        let withBoth = ride.replacingLegs([access, ride.plan.legs[0], egress])
        let visible = RouteOptionVisibility.visibleOptions(primary: [withBoth, direct], supplemental: [], at: anchor)
        #expect(visible.primary.map(\.id) == [direct.id])
    }

    @Test("Cancelled and missed routes cannot hide a usable alternative")
    func unusableOptionsDoNotDominate() {
        let usable = option("usable", mode: .bicycle, departure: -60, arrival: 1_800)
        let cancelled = option("cancelled", departure: 300, arrival: 1_200, liveStatus: .cancelled)
        let missed = option("missed", departure: -31, arrival: 1_200)
        for unusable in [cancelled, missed] {
            let visible = RouteOptionVisibility.visibleOptions(primary: [usable, unusable], supplemental: [], at: anchor)
            #expect(visible.primary.contains { $0.id == usable.id })
        }
    }

    @Test("Unknown departure or arrival times cannot establish dominance")
    func unknownTimesStayVisible() {
        let known = option("known", departure: 300, arrival: 1_200)
        for missingDeparture in [true, false] {
            let incomplete = option("unknown", departure: missingDeparture ? nil : 0,
                                    arrival: missingDeparture ? 1_800 : nil)
            let visible = RouteOptionVisibility.visibleOptions(primary: [incomplete, known], supplemental: [], at: anchor)
            #expect(visible.primary.map(\.id) == [incomplete.id, known.id])
        }
    }

    private func option(_ id: String, mode: TransportMode = .bus,
                        departure: TimeInterval?, arrival: TimeInterval?,
                        realtimeDeparture: TimeInterval? = nil, realtimeArrival: TimeInterval? = nil,
                        liveStatus: RouteLegLiveStatus = .scheduled) -> RouteOption {
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(latitude: 49.61, longitude: 6.1)
        let kind: RouteLegTransportKind = mode == .walking ? .walking : mode == .bicycle ? .bikeShare : .transit
        let leg = RoutePlan.Leg(id: id, mode: mode, transportKind: kind,
            origin: origin, destination: destination,
            departureTime: departure.map { anchor.addingTimeInterval($0) },
            arrivalTime: arrival.map { anchor.addingTimeInterval($0) },
            realtimeDepartureTime: realtimeDeparture.map { anchor.addingTimeInterval($0) },
            realtimeArrivalTime: realtimeArrival.map { anchor.addingTimeInterval($0) },
            liveStatus: liveStatus)
        return RouteOption(id: id, plan: .init(id: id, origin: origin, destination: destination,
            expectedTravelTime: departure.flatMap { start in arrival.map { $0 - start } },
            distanceMeters: 0, legs: [leg], dataSource: .local), mapOverlay: nil)
    }
}
