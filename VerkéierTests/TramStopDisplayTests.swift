import Foundation
import Testing
@testable import Verkeier

@MainActor
struct TramStopDisplayTests {
    @Test func stripsOnlyTheLocalityForTramPresentation() {
        #expect("Luxembourg, Hamilius (Tram)".stationDisplayName(hidingLocality: true) == "Hamilius")
        #expect("Luxembourg, Gare, Quai 1".stationDisplayName(hidingLocality: true) == "Gare, Quai 1")
        #expect("Luxexpo".stationDisplayName(hidingLocality: true) == "Luxexpo")
        #expect("Luxembourg, ".stationDisplayName(hidingLocality: true) == "Luxembourg,")
        #expect("Luxembourg, Gare".stationDisplayName(hidingLocality: false) == "Luxembourg, Gare")
    }

    @Test func retainsLocalityAndFullNameForSearchAndRouting() throws {
        let stop = Stop(id: "tram", name: "Luxembourg, Hamilius (Tram)",
            location: LocationPoint(latitude: 49.61, longitude: 6.13), modes: [.tram], dataSource: .mock)
        #expect(stop.displayName == "Hamilius")
        #expect(stop.name == "Luxembourg, Hamilius")
        #expect(stop.fullName == "Luxembourg, Hamilius")
        #expect(stop.locality == "Luxembourg")
        let decoded = try JSONDecoder().decode(Stop.self, from: JSONEncoder().encode(stop))
        #expect(decoded == stop)
        let place = RoutePlace(stop: stop, source: .search)
        #expect(place.title == "Hamilius")
        #expect(place.subtitle == "Luxembourg")
    }

    @Test func tripRowsUseTheRideModeEvenWhenStopModesAreMissing() {
        let instance = TripRunIdentity(feedGeneration: 1, tripID: "tram", serviceDate: "20261011")
        let stop = Stop(id: "stop", name: "Luxembourg, Hamilius",
            location: LocationPoint(latitude: 49.61, longitude: 6.13), dataSource: .mock)
        let entry = TripStopEntry(sequence: 1, stop: stop, arrival: nil, departure: nil, platform: nil)
        let snapshot = TripDetailSnapshot(instance: instance, stops: [entry], mapOverlay: .init(segments: []),
            isApproximateRoute: true, liveDataAvailable: false, isCancelled: false, fetchedAt: .now)
        let selection = TripDetailSelection(instance: instance, boardingSequence: 1, alightingSequence: 1,
            lineName: "T1", routeShortName: "T1", headsign: "Luxembourg, Stadion", mode: .tram, routeID: nil)
        let rows = TripStopItemBuilder.items(snapshot: snapshot, selection: selection, now: .now, refreshFailed: false)
        #expect(rows.first?.name == "Hamilius")
        #expect(snapshot.stops.first?.stop.fullName == "Luxembourg, Hamilius")
        #expect(selection.headsign == "Luxembourg, Stadion")
    }

    @Test func departureHeadsignsKeepTheirSourceValue() {
        let tram = Departure(id: "tram", stopId: "stop", lineName: "T1",
            destination: "Luxembourg, Stadion", scheduledDeparture: nil, dataSource: .mock, mode: .tram)
        let bus = Departure(id: "bus", stopId: "stop", lineName: "18",
            destination: "Luxembourg, Gare", scheduledDeparture: nil, dataSource: .mock, mode: .bus)
        #expect(tram.displayDestination == "STADION")
        #expect(tram.destination == "Luxembourg, Stadion")
        #expect(bus.displayDestination == "LUXEMBOURG, Gare")
        #expect(bus.destination == "Luxembourg, Gare")

        let tLineBus = Departure(id: "t-bus", stopId: "stop", lineName: "T9",
            destination: "Luxembourg, Gare", scheduledDeparture: nil, dataSource: .mock, mode: .bus)
        #expect(tLineBus.displayDestination == "LUXEMBOURG, Gare")
    }
}

@MainActor
struct HeadsignDisplayTests {
    @Test func busHeadsignLocalityIsUppercased() {
        #expect("Luxembourg, Gare".headsignDisplayName(isTram: false) == "LUXEMBOURG, Gare")
        #expect("Esch/Alzette, Gare (Bus)".headsignDisplayName(isTram: false) == "ESCH/ALZETTE, Gare")
        #expect("Luxexpo".headsignDisplayName(isTram: false) == "Luxexpo")
    }

    @Test func tramHeadsignsOmitLocalityAndAreUppercased() {
        #expect("Luxembourg, Stadion".headsignDisplayName(isTram: true) == "STADION")
        #expect("Luxembourg, Gare, Quai 1".headsignDisplayName(isTram: true) == "GARE, QUAI 1")
        #expect("Luxexpo".headsignDisplayName(isTram: true) == "LUXEXPO")
    }
}
