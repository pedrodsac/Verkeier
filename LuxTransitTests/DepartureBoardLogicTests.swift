import Foundation
import Testing
@testable import LuxTransit

struct DepartureBoardLogicTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func departure(
        id: String,
        line: String,
        at time: Date,
        isCancelled: Bool = false
    ) -> Departure {
        Departure(
            id: id,
            stopId: "stop-1",
            lineName: line,
            destination: "Somewhere",
            scheduledDeparture: time,
            isCancelled: isCancelled,
            dataSource: .mock
        )
    }

    @Test func flagsLastEveningDeparturePerLineOnly() {
        let departures = [
            departure(id: "16-early", line: "16", at: date(17, 50)),
            departure(id: "16-last", line: "16", at: date(19, 30)),
            departure(id: "t1-early", line: "T1", at: date(16, 0)),
            departure(id: "t1-last", line: "T1", at: date(17, 0)) // latest is before 18:00
        ]

        let ids = lastServiceDepartureIDs(in: departures, calendar: calendar)

        #expect(ids == ["16-last"])
    }

    @Test func ignoresCancelledTripsWhenPickingLastService() {
        let departures = [
            departure(id: "29-real", line: "29", at: date(19, 0)),
            departure(id: "29-cancelled", line: "29", at: date(22, 0), isCancelled: true)
        ]

        let ids = lastServiceDepartureIDs(in: departures, calendar: calendar)

        #expect(ids == ["29-real"])
    }

    @Test func returnsEmptyWhenNothingRunsAfterCutoff() {
        let departures = [
            departure(id: "morning", line: "30", at: date(7, 15)),
            departure(id: "noon", line: "30", at: date(12, 0))
        ]

        #expect(lastServiceDepartureIDs(in: departures, calendar: calendar).isEmpty)
    }
}
