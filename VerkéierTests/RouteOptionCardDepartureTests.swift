import Foundation
import Testing
@testable import Verkeier

@Suite("Route option departed state")
@MainActor
struct RouteOptionCardDepartureTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: hour, minute: minute, second: second))!
    }

    @Test("A route that left one minute ago stays active")
    func leftOneMinuteAgoIsActive() {
        #expect(!RouteOptionCard.hasDeparted(date(17, 59), at: date(18, 0), calendar: calendar))
    }

    @Test("A route that left two minutes ago is greyed out")
    func leftTwoMinutesAgoIsGreyed() {
        #expect(RouteOptionCard.hasDeparted(date(17, 58), at: date(18, 0), calendar: calendar))
    }

    @Test("Seconds within the current minute do not change the outcome")
    func secondsAreIgnored() {
        #expect(!RouteOptionCard.hasDeparted(date(17, 59, 59), at: date(18, 0, 30), calendar: calendar))
        #expect(RouteOptionCard.hasDeparted(date(17, 58, 0), at: date(18, 0, 59), calendar: calendar))
    }

    @Test("Future departures and missing times are never greyed")
    func futureAndMissingAreActive() {
        #expect(!RouteOptionCard.hasDeparted(date(18, 30), at: date(18, 0), calendar: calendar))
        #expect(!RouteOptionCard.hasDeparted(nil, at: date(18, 0), calendar: calendar))
    }
}
