import Foundation

/// A timetabled departure computed from the offline GTFS index.
struct OfflineScheduleDeparture: Identifiable, Equatable {
    /// Stable identifier for the departure.
    let id: String
    /// Public line label.
    let lineName: String
    /// Trip headsign / destination.
    let destination: String
    /// Scheduled departure date and time.
    let departureDate: Date
    /// Boarding platform, when published.
    let platform: String?
    /// Transport mode of the trip.
    let mode: TransportMode
}

/// Computes upcoming departures for a stop purely from the offline GTFS
/// timetable, with no network access.
///
/// Used as a fallback when live ATP data is unavailable. All time arithmetic is
/// done in the `Europe/Luxembourg` time zone by default.
struct OfflineScheduleService {
    private let calendar: Calendar

    init(calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
        return calendar
    }()) {
        self.calendar = calendar
    }

    /// Computes the next departures from a stop using the offline timetable.
    ///
    /// Only services active on `now`'s date are considered.
    /// - Parameters:
    ///   - stop: The stop to compute departures for.
    ///   - timetable: The offline timetable index (see
    ///     ``GTFSService/timetableIndex()``).
    ///   - now: Reference time; departures before it are excluded.
    ///   - limit: Maximum number of departures to return.
    /// - Returns: Upcoming departures sorted by time, or `[]` when none apply.
    func upcomingDepartures(
        for stop: Stop,
        timetable: GTFSTimetableIndexPayload,
        now: Date = .now,
        limit: Int = 8
    ) -> [OfflineScheduleDeparture] {
        guard limit > 0 else { return [] }

        let routesById = Dictionary(uniqueKeysWithValues: timetable.routes.map { ($0.id, $0) })
        let stopsById = Dictionary(uniqueKeysWithValues: timetable.stops.map { ($0.id, $0) })
        let activeServiceIds = Set(
            timetable.services.filter { isActive($0, on: now) }.map(\.id)
        )
        guard !activeServiceIds.isEmpty else { return [] }

        let candidateStopIds = matchingStopIDs(for: stop, in: timetable)
        guard !candidateStopIds.isEmpty else { return [] }

        let startOfDay = calendar.startOfDay(for: now)
        let currentSeconds = calendar.dateComponents([.hour, .minute, .second], from: now)
        let secondsSinceMidnight =
            (currentSeconds.hour ?? 0) * 3600
                + (currentSeconds.minute ?? 0) * 60
                + (currentSeconds.second ?? 0)

        let departures = timetable.trips
            .lazy
            .filter { activeServiceIds.contains($0.serviceId) }
            .flatMap { trip in
                trip.stopTimes.compactMap { stopTime -> OfflineScheduleDeparture? in
                    guard candidateStopIds.contains(stopTime.stopId),
                          stopTime.departureSeconds >= secondsSinceMidnight,
                          let route = routesById[trip.routeId] else {
                        return nil
                    }

                    let stopEntry = stopsById[stopTime.stopId]
                    let departureDate = startOfDay.addingTimeInterval(TimeInterval(stopTime.departureSeconds))
                    return OfflineScheduleDeparture(
                        id: "\(trip.id)-\(stopTime.stopId)-\(stopTime.sequence)",
                        lineName: route.shortName,
                        destination: stopTime.headsign ?? trip.headsign ?? route.longName ?? stop.name,
                        departureDate: departureDate,
                        platform: stopEntry?.platformCode,
                        mode: route.transportMode
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.departureDate != rhs.departureDate {
                    return lhs.departureDate < rhs.departureDate
                }
                return lhs.lineName.localizedStandardCompare(rhs.lineName) == .orderedAscending
            }

        return Array(departures.prefix(limit))
    }

    private func matchingStopIDs(
        for stop: Stop,
        in timetable: GTFSTimetableIndexPayload
    ) -> Set<String> {
        let directIDs = Set(stop.platformIds)
        let timetableStopIDs = Set(timetable.stops.map(\.id))
        var matches = directIDs.intersection(timetableStopIDs)

        if timetableStopIDs.contains(stop.id) {
            matches.insert(stop.id)
        }

        if !matches.isEmpty {
            let childStops = timetable.stops
                .filter { entry in
                    matches.contains(entry.parentStation ?? "")
                }
                .map(\.id)
            matches.formUnion(childStops)
            return matches
        }

        let normalizedName = stop.name.normalizedForSearch
        let nearbyNameMatches = timetable.stops.filter { entry in
            entry.name.normalizedForSearch == normalizedName
        }
        return Set(nearbyNameMatches.map(\.id))
    }

    private func isActive(_ service: GTFSTimetableServiceEntry, on date: Date) -> Bool {
        let dateString = serviceDateString(for: date)
        if service.removedDates.contains(dateString) {
            return false
        }
        if service.addedDates.contains(dateString) {
            return true
        }

        if let startDate = service.startDate, dateString < startDate {
            return false
        }
        if let endDate = service.endDate, dateString > endDate {
            return false
        }

        // `weekdays` is stored in Foundation order (Sun=1 ... Sat=7) by
        // GTFSIndexBuilder, matching `Calendar.component(.weekday:)`. Compare directly —
        // the routing engine uses the same raw value. (An earlier ISO conversion here
        // silently shifted every service by one day against real feed data.)
        return service.weekdays.contains(calendar.component(.weekday, from: date))
    }

    private func serviceDateString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
