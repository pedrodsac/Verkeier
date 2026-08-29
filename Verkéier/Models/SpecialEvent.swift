import Foundation

/// A date-bounded event that can be promoted on the home sheet.
struct SpecialEvent: Identifiable, Equatable, Sendable {
    enum ColorToken: String, Equatable, Sendable {
        case pink
    }

    let id: String
    let title: String
    let subtitle: String
    let stopName: String
    let symbolName: String
    let accentColor: ColorToken
    let backgroundColor: ColorToken
    let startDate: Date
    let endDate: Date

    /// Returns true for every calendar day from `startDate` through `endDate`.
    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        return day >= startDay && day <= endDay
    }
}

enum SpecialEventCatalog {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static let allEvents: [SpecialEvent] = [
        SpecialEvent(
            id: "schueberfouer-2026",
            title: "Schueberfouer",
            subtitle: "Glacis, Limpertsberg",
            stopName: "Limpertsberg, Theater",
            symbolName: "party.popper.fill",
            accentColor: .pink,
            backgroundColor: .pink,
            startDate: date(year: 2026, month: 8, day: 21),
            endDate: date(year: 2026, month: 9, day: 9)
        )
    ]

    static func activeEvents(on date: Date = .now) -> [SpecialEvent] {
        allEvents.filter { $0.isActive(on: date, calendar: calendar) }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
