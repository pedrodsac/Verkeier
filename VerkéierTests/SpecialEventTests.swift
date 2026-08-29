import Foundation
import Testing
@testable import Verkeier

struct SpecialEventTests {
    @Test func schueberfouerIsActiveOnInclusiveBoundaryDates() throws {
        let event = try #require(SpecialEventCatalog.allEvents.first)

        #expect(event.isActive(on: date(year: 2026, month: 8, day: 21)))
        #expect(event.isActive(on: date(year: 2026, month: 9, day: 9)))
    }

    @Test func schueberfouerIsInactiveOutsideItsDateRange() throws {
        let event = try #require(SpecialEventCatalog.allEvents.first)

        #expect(!event.isActive(on: date(year: 2026, month: 8, day: 20)))
        #expect(!event.isActive(on: date(year: 2026, month: 9, day: 10)))
    }

    @Test func catalogContainsRequestedSchueberfouerConfiguration() throws {
        let event = try #require(SpecialEventCatalog.allEvents.first)

        #expect(event.id == "schueberfouer-2026")
        #expect(event.title == "Schueberfouer")
        #expect(event.subtitle == "Glacis, Limpertsberg")
        #expect(event.stopName == "Limpertsberg, Theater")
        #expect(event.symbolName == "tent.2.fill")
        #expect(event.accentColor == .pink)
        #expect(event.backgroundColor == .pink)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
