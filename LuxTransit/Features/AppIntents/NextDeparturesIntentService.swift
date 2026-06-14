import Foundation

enum NextDeparturesIntentService {
    static func response(for stop: FavouriteStopEntity) async -> String {
        await response(for: stop, configuration: .current)
    }

    static func response(for stop: FavouriteStopEntity, configuration: AppConfiguration) async -> String {
        guard configuration.hasATPAccessId else {
            return "Live ATP departures are not configured. Open LuxTransit to use local favourites and search."
        }

        do {
            let departures = try await LiveATPClient(configuration: configuration)
                .departureBoard(stopId: stop.id)
            return summary(for: stop, departures: departures)
        } catch ATPClientError.missingAccessId {
            return "Live ATP departures are not configured. Open LuxTransit to use local favourites and search."
        } catch {
            return "Live departures for \(stop.name) could not be loaded right now."
        }
    }

    static func summary(
        for stop: FavouriteStopEntity,
        departures: [Departure],
        now: Date = .now
    ) -> String {
        let upcomingDepartures = departures
            .filter { departure in
                guard let date = departure.realtimeDeparture ?? departure.scheduledDeparture else {
                    return true
                }
                return date >= now.addingTimeInterval(-60)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.realtimeDeparture ?? lhs.scheduledDeparture ?? .distantFuture
                let rhsDate = rhs.realtimeDeparture ?? rhs.scheduledDeparture ?? .distantFuture
                return lhsDate < rhsDate
            }
            .prefix(3)

        guard !upcomingDepartures.isEmpty else {
            return "No upcoming live departures are available for \(stop.name)."
        }

        let rows = upcomingDepartures.map { departure in
            "\(departure.lineName) to \(departure.destination), \(timeText(for: departure, now: now)), \(departure.status.displayText)"
        }

        return "Next departures from \(stop.name): " + rows.joined(separator: "; ")
    }

    private static func timeText(for departure: Departure, now: Date) -> String {
        guard let departureDate = departure.realtimeDeparture ?? departure.scheduledDeparture else {
            return "time unknown"
        }

        let minutes = Int(departureDate.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "now" }
        if minutes < 90 { return "in \(minutes) min" }

        return departureDate.formatted(date: .omitted, time: .shortened)
    }
}
