import Foundation
import MobiliteitKit
import Testing

@testable import Verkeier

struct HafasDepartureReadingTests {
    @Test func readsLuxembourgLocalTimesWithAndWithoutSeconds() throws {
        let withSeconds = try #require(HafasDepartureReading.date(date: "2026-11-15", time: "10:02:30"))
        let withoutSeconds = try #require(HafasDepartureReading.date(date: "2026-11-15", time: "10:02"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Luxembourg"))
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10, minute: 2))
        )
        #expect(withoutSeconds == expected)
        #expect(withSeconds == expected.addingTimeInterval(30))
        #expect(HafasDepartureReading.date(date: nil, time: "10:02") == nil)
    }

    @Test func realtimeFallsBackToThePlannedDate() throws {
        let departure = try decode(
            #"{"name":"16","direction":"Findel, Airport","date":"2026-11-15","time":"10:00:00","rtTime":"10:03:00"}"#
        )
        let scheduled = try #require(HafasDepartureReading.scheduledDate(of: departure))
        let realtime = try #require(HafasDepartureReading.realtimeDate(of: departure))
        #expect(realtime.timeIntervalSince(scheduled) == 180)
        #expect(HafasDepartureReading.lineName(of: departure) == "16")
        #expect(HafasDepartureReading.destination(of: departure) == "Findel, Airport")
    }

    @Test func blankDirectionReadsAsUnknownDestination() throws {
        let departure = try decode(#"{"direction":"  ","date":"2026-11-15","time":"10:00"}"#)
        #expect(HafasDepartureReading.destination(of: departure) == "Unknown destination")
        #expect(HafasDepartureReading.lineName(of: departure) == "Service")
    }

    @Test func terminalArrivalMatchesTheDirectionWithoutAPassList() throws {
        let arrival = try decode(#"{"direction":"Hamilius","date":"2026-11-15","time":"10:00"}"#)
        let departure = try decode(#"{"direction":"Kirchberg","date":"2026-11-15","time":"10:00"}"#)
        #expect(HafasDepartureReading.isTerminalArrival(arrival, stopIdentifiers: ["1"], stopName: "Hamilius"))
        #expect(!HafasDepartureReading.isTerminalArrival(departure, stopIdentifiers: ["1"], stopName: "Hamilius"))
    }

    @Test func lineKindPrefersBusThenTramThenTrain() {
        let bus = HafasProductClass.bus.rawValue
        let tram = HafasProductClass.tram.rawValue
        let train = HafasProductClass.localTrain.rawValue
        #expect(HafasDepartureReading.lineKind(productClass: bus | tram) == .bus)
        #expect(HafasDepartureReading.lineKind(productClass: tram) == .tram)
        #expect(HafasDepartureReading.lineKind(productClass: train) == .train)
        #expect(HafasDepartureReading.lineKind(productClass: 0) == nil)
        #expect(HafasDepartureReading.lineKind(productClass: nil) == nil)
    }

    @Test func favouriteStopKeepsItsLiveStationIDAndOlderPayloadsDecode() throws {
        var stop = SharedFavouriteStop(id: "gtfs:200403005", name: "Hamilius", locality: "Luxembourg")
        stop.liveStationID = "200403005"
        let roundTripped = try JSONDecoder().decode(
            SharedFavouriteStop.self,
            from: JSONEncoder().encode(stop)
        )
        #expect(roundTripped.liveStationID == "200403005")

        let older = Data(#"{"id":"1","name":"Hamilius","platformIds":["1"]}"#.utf8)
        #expect(try JSONDecoder().decode(SharedFavouriteStop.self, from: older).liveStationID == nil)
    }

    private func decode(_ json: String) throws -> HafasDeparture {
        try JSONDecoder().decode(HafasDeparture.self, from: Data(json.utf8))
    }
}
