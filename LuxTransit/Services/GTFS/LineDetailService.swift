import Foundation

/// Builds a ``LineDetail`` for a route from the offline GTFS timetable.
///
/// Groups a route's trips into directions, derives the stop sequence and the
/// next departures for the selected direction, and assembles a map overlay. All
/// time arithmetic uses the `Europe/Luxembourg` time zone by default.
struct LineDetailService {
    private let calendar: Calendar

    init(calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
        return calendar
    }()) {
        self.calendar = calendar
    }

    /// Builds line detail for a route, or `nil` when the timetable has no trips
    /// for it.
    /// - Parameters:
    ///   - route: The route to describe.
    ///   - selectedStopId: A stop to anchor/highlight in the sequence, if any.
    ///   - timetable: The offline timetable index.
    ///   - now: Reference time used to pick active services and next departures.
    ///   - selectedDirectionID: The direction to show; defaults to the first.
    func detail(
        for route: TransitRoute,
        selectedStopId: String?,
        timetable: GTFSTimetableIndexPayload,
        now: Date = .now,
        selectedDirectionID: String? = nil
    ) -> LineDetail? {
        let routeEntry = timetable.routes.first(where: { $0.id == route.id }) ?? GTFSTimetableRouteEntry(
            id: route.id,
            shortName: route.shortName,
            longName: route.longName,
            mode: route.mode.rawValue,
            operatorName: route.operatorName
        )
        let trips = timetable.trips.filter { $0.routeId == route.id }
        guard !trips.isEmpty else { return nil }

        let stopEntriesById = Dictionary(uniqueKeysWithValues: timetable.stops.map { ($0.id, $0) })
        let activeServiceIds = activeServiceIDs(in: timetable.services, now: now)

        let groupedTrips = Dictionary(grouping: trips) { trip in
            directionKey(for: trip)
        }

        let directions = groupedTrips.keys.sorted().compactMap { key -> LineDetailDirection? in
            guard let sample = groupedTrips[key]?.first else { return nil }
            return LineDetailDirection(
                id: key,
                title: directionTitle(for: sample, route: routeEntry).stationDisplayName,
                subtitle: sample.directionId.map { "Direction \($0)" }
            )
        }
        guard !directions.isEmpty else { return nil }

        let resolvedDirectionID = selectedDirectionID.flatMap { candidate in
            directions.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? preferredDirectionID(
            directions: directions,
            groupedTrips: groupedTrips,
            selectedStopId: selectedStopId,
            activeServiceIds: activeServiceIds,
            now: now
        )

        guard let selectedDirectionTrips = groupedTrips[resolvedDirectionID], !selectedDirectionTrips.isEmpty else {
            return nil
        }

        let representativeTrip = representativeTrip(
            trips: selectedDirectionTrips,
            selectedStopId: selectedStopId,
            activeServiceIds: activeServiceIds,
            now: now
        ) ?? selectedDirectionTrips[0]

        let stopSequence = representativeTrip.stopTimes.compactMap { stopTime -> LineStopSequenceEntry? in
            guard let stop = stopEntriesById[stopTime.stopId] else { return nil }
            return LineStopSequenceEntry(
                id: stop.id,
                name: stop.name.stationDisplayName,
                platform: stop.platformCode,
                location: stop.location
            )
        }

        let upcomingDepartures = makeUpcomingDepartures(
            from: selectedDirectionTrips,
            selectedStopId: selectedStopId,
            activeServiceIds: activeServiceIds,
            stopEntriesById: stopEntriesById,
            now: now
        )

        return LineDetail(
            route: route,
            directions: directions,
            selectedDirectionID: resolvedDirectionID,
            stopSequence: stopSequence,
            upcomingDepartures: upcomingDepartures,
            serviceSummary: serviceSummary(
                from: selectedDirectionTrips,
                activeServiceIds: activeServiceIds,
                stopEntriesById: stopEntriesById
            ),
            mapOverlay: overlay(for: representativeTrip, route: route, stopsById: stopEntriesById, shapes: timetable.shapes)
        )
    }

    private func activeServiceIDs(
        in services: [GTFSTimetableServiceEntry],
        now: Date
    ) -> Set<String> {
        Set(services.filter { isActive($0, now: now) }.map(\.id))
    }

    private func isActive(_ service: GTFSTimetableServiceEntry, now: Date) -> Bool {
        let dateString = isoDateString(for: now)
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

        let weekday = calendar.component(.weekday, from: now)
        return service.weekdays.contains(weekday)
    }

    private func isoDateString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func directionKey(for trip: GTFSTimetableTripEntry) -> String {
        let direction = trip.directionId ?? "0"
        let headsign = trip.headsign?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "route"
        return "\(direction)|\(headsign)"
    }

    private func directionTitle(
        for trip: GTFSTimetableTripEntry,
        route: GTFSTimetableRouteEntry
    ) -> String {
        if let headsign = trip.headsign?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return headsign
        }
        return route.longName ?? route.shortName
    }

    private func preferredDirectionID(
        directions: [LineDetailDirection],
        groupedTrips: [String: [GTFSTimetableTripEntry]],
        selectedStopId: String?,
        activeServiceIds: Set<String>,
        now: Date
    ) -> String {
        let scored = directions.map { direction in
            let trips = groupedTrips[direction.id] ?? []
            let nextTime = nextDepartureSeconds(
                in: trips,
                selectedStopId: selectedStopId,
                activeServiceIds: activeServiceIds,
                now: now
            )
            return (direction.id, nextTime)
        }
        return scored.min { ($0.1 ?? .max) < ($1.1 ?? .max) }?.0 ?? directions[0].id
    }

    private func representativeTrip(
        trips: [GTFSTimetableTripEntry],
        selectedStopId: String?,
        activeServiceIds: Set<String>,
        now: Date
    ) -> GTFSTimetableTripEntry? {
        let targetSeconds = secondsSinceMidnight(for: now)
        let filtered = trips.filter { activeServiceIds.contains($0.serviceId) }
        let candidates = filtered.isEmpty ? trips : filtered
        return candidates.min { lhs, rhs in
            let lhsSeconds = tripReferenceSeconds(lhs, selectedStopId: selectedStopId) ?? .max
            let rhsSeconds = tripReferenceSeconds(rhs, selectedStopId: selectedStopId) ?? .max
            return abs(lhsSeconds - targetSeconds) < abs(rhsSeconds - targetSeconds)
        }
    }

    private func nextDepartureSeconds(
        in trips: [GTFSTimetableTripEntry],
        selectedStopId: String?,
        activeServiceIds: Set<String>,
        now: Date
    ) -> Int? {
        let targetSeconds = secondsSinceMidnight(for: now)
        return trips
            .filter { activeServiceIds.contains($0.serviceId) }
            .compactMap { tripReferenceSeconds($0, selectedStopId: selectedStopId) }
            .filter { $0 >= targetSeconds }
            .min()
    }

    private func tripReferenceSeconds(
        _ trip: GTFSTimetableTripEntry,
        selectedStopId: String?
    ) -> Int? {
        if let selectedStopId,
           let matching = trip.stopTimes.first(where: { $0.stopId == selectedStopId }) {
            return matching.departureSeconds
        }
        return trip.stopTimes.first?.departureSeconds
    }

    private func makeUpcomingDepartures(
        from trips: [GTFSTimetableTripEntry],
        selectedStopId: String?,
        activeServiceIds: Set<String>,
        stopEntriesById: [String: GTFSTimetableStopEntry],
        now: Date
    ) -> [LineTimetableEntry] {
        let startOfDay = calendar.startOfDay(for: now)
        let targetSeconds = secondsSinceMidnight(for: now)

        return trips
            .filter { activeServiceIds.contains($0.serviceId) }
            .compactMap { trip -> LineTimetableEntry? in
                guard let stopTime = selectedStopId.flatMap({ id in
                    trip.stopTimes.first(where: { $0.stopId == id })
                }) ?? trip.stopTimes.first,
                stopTime.departureSeconds >= targetSeconds,
                let originStopId = trip.stopTimes.first?.stopId,
                let destinationStopId = trip.stopTimes.last?.stopId else {
                    return nil
                }

                let departureTime = startOfDay.addingTimeInterval(TimeInterval(stopTime.departureSeconds))
                return LineTimetableEntry(
                    id: "\(trip.id)-\(stopTime.stopId)",
                    departureTime: departureTime,
                    originName: stopEntriesById[originStopId]?.name.stationDisplayName ?? "Origin",
                    destinationName: stopEntriesById[destinationStopId]?.name.stationDisplayName
                        ?? trip.headsign?.stationDisplayName ?? "Destination"
                )
            }
            .sorted { $0.departureTime < $1.departureTime }
            .prefix(12)
            .map { $0 }
    }

    private func serviceSummary(
        from trips: [GTFSTimetableTripEntry],
        activeServiceIds: Set<String>,
        stopEntriesById: [String: GTFSTimetableStopEntry]
    ) -> String {
        let activeTrips = trips.filter { activeServiceIds.contains($0.serviceId) }
        guard let earliest = activeTrips.compactMap(\.stopTimes.first?.departureSeconds).min(),
              let latest = activeTrips.compactMap(\.stopTimes.last?.arrivalSeconds).max(),
              let firstTrip = activeTrips.first,
              let originName = firstTrip.stopTimes.first.flatMap({ stopEntriesById[$0.stopId]?.name.stationDisplayName }),
              let destinationName = firstTrip.stopTimes.last.flatMap({ stopEntriesById[$0.stopId]?.name.stationDisplayName }) else {
            return "Static timetable preview"
        }

        return "\(originName) to \(destinationName) · \(timeText(for: earliest))–\(timeText(for: latest))"
    }

    private func overlay(
        for trip: GTFSTimetableTripEntry,
        route: TransitRoute,
        stopsById: [String: GTFSTimetableStopEntry],
        shapes: [GTFSTimetableShapeEntry]
    ) -> RouteMapOverlay? {
        if let shapeId = trip.shapeId,
           let shape = shapes.first(where: { $0.id == shapeId }),
           shape.points.count >= 2 {
            let coordinates = shape.points
                .sorted { $0.sequence < $1.sequence }
                .map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            return RouteMapOverlay(segments: [
                RouteMapSegment(
                    id: "\(route.id)-shape",
                    mode: route.mode,
                    routeName: route.shortName,
                    routeId: route.id,
                    coordinates: coordinates
                )
            ])
        }

        let coordinates = trip.stopTimes.compactMap { stopTime in
            stopsById[stopTime.stopId].map { RouteMapCoordinate($0.location) }
        }
        guard coordinates.count >= 2 else { return nil }

        return RouteMapOverlay(segments: [
            RouteMapSegment(
                id: "\(route.id)-stops",
                mode: route.mode,
                routeName: route.shortName,
                routeId: route.id,
                coordinates: coordinates
            )
        ])
    }

    private func secondsSinceMidnight(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }

    private func timeText(for seconds: Int) -> String {
        let hour = (seconds / 3600) % 24
        let minute = (seconds % 3600) / 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
