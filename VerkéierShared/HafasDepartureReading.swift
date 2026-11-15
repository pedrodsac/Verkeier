import Foundation
import MobiliteitKit

/// ATP departure-board field rules shared by the app's live board and the
/// widget extension, so both read a HAFAS row the same way.
nonisolated enum HafasDepartureReading {
    /// Parses an ATP date and time, which are local to Luxembourg.
    static func date(date: String?, time: String?) -> Date? {
        guard let date, let time else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let value = formatter.date(from: "\(date) \(time)") { return value }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    static func scheduledDate(of departure: HafasDeparture) -> Date? {
        date(date: departure.plannedDate, time: departure.plannedTime)
    }

    static func realtimeDate(of departure: HafasDeparture) -> Date? {
        date(date: departure.realtimeDate ?? departure.plannedDate, time: departure.realtimeTime)
    }

    static func lineName(of departure: HafasDeparture) -> String {
        let product = departure.product
        return product?.line ?? departure.name ?? product?.name ?? product?.categoryShort ?? "Service"
    }

    static func destination(of departure: HafasDeparture) -> String {
        let trimmed = departure.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown destination" : trimmed
    }

    static func platform(of departure: HafasDeparture) -> String? {
        firstNonempty(departure.realtimePlatform?.text, departure.platform?.text)
    }

    /// The vehicle kind from an ATP product class, in the same precedence the
    /// app uses for its transport mode: bus, then tram, then train.
    static func lineKind(productClass: Int?) -> LineKind? {
        guard let productClass else { return nil }
        if productClass & HafasProductClass.bus.rawValue != 0 { return .bus }
        if productClass & HafasProductClass.tram.rawValue != 0 { return .tram }
        let trains =
            HafasProductClass.expressTrain.rawValue
            | HafasProductClass.nationalTrain.rawValue
            | HafasProductClass.localTrain.rawValue
        return productClass & trains != 0 ? .train : nil
    }

    /// Whether the row is an arrival at its terminus, `stopName`.
    ///
    /// HAFAS can return such an arrival as a departure-board row. There is
    /// nowhere for a rider to travel from there, so every consumer of the live
    /// board omits it.
    static func isTerminalArrival(
        _ departure: HafasDeparture,
        stopIdentifiers: [String],
        stopName: String
    ) -> Bool {
        if let lastStop = departure.passlist.values.last {
            let identifiers = Set(
                stopIdentifiers
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            let lastStopIdentifiers = [lastStop.id, lastStop.externalID]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if lastStopIdentifiers.contains(where: identifiers.contains) {
                return true
            }
            if let name = lastStop.name, name.identifiesSameStation(as: stopName) {
                return true
            }
        }

        // Direction is the terminus label and remains the fallback for HAFAS
        // responses whose pass list is absent or uses unrelated identifiers.
        return departure.direction?.identifiesSameStation(as: stopName) == true
    }

    static func firstNonempty(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }
}
