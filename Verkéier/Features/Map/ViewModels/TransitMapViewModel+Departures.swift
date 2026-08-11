import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func loadFavouriteDepartures(using atpClient: any ATPClient, favourites: [Stop]) async {
        let limitedFavourites = Array(favourites.prefix(6))

        guard !limitedFavourites.isEmpty else {
            favouriteDeparturesByStopId = [:]
            favouriteDeparturesErrorMessage = nil
            favouriteDeparturesLastUpdated = nil
            isLoadingFavouriteDepartures = false
            return
        }

        isLoadingFavouriteDepartures = true
        favouriteDeparturesErrorMessage = nil

        let results = await loadFavouriteDepartureBoards(
            using: atpClient,
            favourites: limitedFavourites
        )
        let boards = Dictionary(uniqueKeysWithValues: results.map { ($0.stopId, $0.departures) })
        let failedCount = results.filter(\.didFail).count

        favouriteDeparturesByStopId = boards
        favouriteDeparturesLastUpdated = .now
        favouriteDeparturesErrorMessage =
            failedCount == limitedFavourites.count
                ? "Favourite departures could not be loaded." : nil
        isLoadingFavouriteDepartures = false
    }

    func loadDepartures(using atpClient: any ATPClient) async {
        guard let selectedStop else { return }
        isLoadingDepartures = true
        departuresErrorMessage = nil

        do {
            let refreshedDepartures = try await atpClient.departureBoards(stopIds: selectedStop.platformIds)
            departures = departuresWithPlatformFallback(
                in: refreshedDepartures,
                from: departures
            )
            departuresLastUpdated = .now
        } catch {
            // Keep the last successful live board visible while the existing
            // data is marked stale. Clearing it here forces the UI onto the
            // static fallback, which can legitimately have no platform data.
            departuresErrorMessage = "Departures could not be loaded."
        }

        isLoadingDepartures = false
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        if selectedDepartureLine == route.id {
            selectedDepartureLine = nil
        } else {
            selectedDepartureLine = route.id
        }

        clearSelectedPlatformIfUnavailable()
    }

    func selectDeparturePlatform(_ platform: String?) {
        selectedDeparturePlatform = platform
    }

    func loadOfflineScheduledDepartures(
        using gtfsService: any GTFSService,
        now: Date = .now
    ) async {
        guard let selectedStop,
              let timetable = await gtfsService.timetableIndex() else {
            offlineScheduledDepartures = []
            return
        }

        let service = OfflineScheduleService()
        offlineScheduledDepartures = service.upcomingDepartures(
            for: selectedStop,
            timetable: timetable,
            now: now
        )
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        guard let favouriteDeparturesLastUpdated else { return false }
        return Date().timeIntervalSince(favouriteDeparturesLastUpdated) > 90
    }

    private func departuresWithPlatformFallback(
        in refreshed: [Departure],
        from previous: [Departure]
    ) -> [Departure] {
        var candidatesByKey: [String: Set<String>] = [:]
        for departure in previous {
            guard let platform = normalizedPlatform(departure.platform) else { continue }
            candidatesByKey[platformFallbackKey(for: departure), default: []].insert(platform)
        }

        return refreshed.map { departure in
            guard normalizedPlatform(departure.platform) == nil,
                  let candidates = candidatesByKey[platformFallbackKey(for: departure)],
                  candidates.count == 1,
                  let platform = candidates.first else {
                return departure
            }
            return departure.replacingPlatform(with: platform)
        }
    }

    private func platformFallbackKey(for departure: Departure) -> String {
        [
            departure.stopId,
            departure.routeId ?? departure.lineName,
            departure.destination,
            departure.scheduledDeparture?.timeIntervalSince1970.description
                ?? departure.realtimeDeparture?.timeIntervalSince1970.description
                ?? ""
        ].joined(separator: "|")
    }

    private func normalizedPlatform(_ platform: String?) -> String? {
        guard let platform else { return nil }
        let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
