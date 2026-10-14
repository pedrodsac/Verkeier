import Foundation
import MobiliteitKit

extension MobiliteitRouteService {
    nonisolated func selection(for departure: Departure, at stop: Stop) async throws -> TripDetailSelection {
        guard let scheduled = departure.scheduledDeparture else { throw TripDetailError.unavailable }
        var stopID = stop.gtfsStopID
        if stopID == nil {
            stopID = await gtfsService?.matchLiveStop(
                .init(
                    stationID: departure.stopId,
                    externalID: nil,
                    name: stop.name,
                    location: stop.location,
                    distanceMeters: nil,
                    modes: []
                )
            )?.gtfsStopID
        }
        guard let stopID else { throw TripDetailError.unavailable }
        let database = try await readyDatabaseURL()
        let store = try GTFSStore(databaseAt: database)
        let feed = await store.feedInfo()
        let candidates = try await store.nextScheduledDepartures(
            fromStopID: stopID,
            at: scheduled.addingTimeInterval(-60),
            horizon: 120,
            limit: 100
        )
        // Scheduled minute and line identify a run. Never use the live clock
        // for matching: delays can put a different vehicle at the same time.
        let matches = candidates.filter { candidate in
            guard
                let time = MobiliteitGTFSService.date(
                    for: candidate.departure,
                    serviceDay: candidate.serviceDay,
                    feed: feed
                ),
                Int(time.timeIntervalSince1970 / 60) == Int(scheduled.timeIntervalSince1970 / 60)
            else { return false }
            return candidate.route.shortName?.localizedCaseInsensitiveCompare(departure.lineName) == .orderedSame
        }
        guard matches.count == 1, let match = matches.first else { throw TripDetailError.unavailable }
        let stops = try await store.stopTimes(forTripID: match.tripID)
        let occurrences = stops.filter { $0.stop.id == match.stopID && $0.departure == match.departure }
        guard occurrences.count == 1, let boarding = occurrences.first, let last = stops.last else {
            throw TripDetailError.unavailable
        }
        try Task.checkCancellation()
        guard try await readyDatabaseURL() == database else { throw TripDetailError.obsoleteFeed }
        let route = MobiliteitGTFSService.route(match.route, agency: match.agency)
        return TripDetailSelection(
            instance: .init(
                feedGeneration: feed.generation,
                tripID: match.tripID,
                serviceDate: feed.firstServiceDate.adding(days: Int(match.serviceDay.index)).compactString
            ),
            boardingSequence: boarding.sequence,
            alightingSequence: last.sequence,
            lineName: departure.lineName,
            routeShortName: route.shortName,
            headsign: departure.destination,
            mode: route.mode,
            routeID: route.id
        )
    }
}
