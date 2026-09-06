import Foundation

enum DepartureTrackingSelection {
    static func nextTrackableDeparture(
        from departures: [Departure],
        now: Date = .now
    ) -> Departure? {
        sortedUpcomingDepartures(from: departures, now: now)
            .first { !$0.isCancelled }
            ?? sortedUpcomingDepartures(from: departures, now: now).first
    }

    static func trackedDeparture(
        in departures: [Departure],
        trackedDepartureId: String?
    ) -> Departure? {
        guard let trackedDepartureId else { return nil }
        return departures.first { $0.id == trackedDepartureId }
    }

    private static func sortedUpcomingDepartures(
        from departures: [Departure],
        now: Date
    ) -> [Departure] {
        departures
            .filter { departure in
                guard let date = departure.realtimeDeparture ?? departure.scheduledDeparture else {
                    return true
                }
                return SharedDepartureTiming.isVisible(date, at: now)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.realtimeDeparture ?? lhs.scheduledDeparture ?? .distantFuture
                let rhsDate = rhs.realtimeDeparture ?? rhs.scheduledDeparture ?? .distantFuture
                return lhsDate < rhsDate
            }
    }
}
