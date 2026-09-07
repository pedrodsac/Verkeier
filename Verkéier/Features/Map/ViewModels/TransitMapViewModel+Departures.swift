import CoreLocation
import MapKit
import Observation
import SwiftUI
import WidgetKit

extension TransitMapViewModel {
    func loadFavouriteDepartures(
        using atpClient: any ATPClient,
        favourites: [Stop],
        filtersByStopID: [String: TransitBoardFilter] = [:]
    ) async {
        guard !favourites.isEmpty else {
            favouriteDepartureBoards = [:]
            isLoadingFavouriteDepartures = false
            return
        }

        isLoadingFavouriteDepartures = true
        for stop in favourites {
            var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
            snapshot.phase = .loading
            snapshot.errorMessage = nil
            favouriteDepartureBoards[stop.id] = snapshot
        }

        let results = await loadFavouriteDepartureBoards(
            using: atpClient,
            favourites: favourites,
            filtersByStopID: filtersByStopID
        )
        let refreshedAt = Date.now
        for result in results {
            guard let stop = favourites.first(where: { $0.id == result.stopId }) else { continue }
            var snapshot = favouriteDepartureBoards[result.stopId] ?? FavouriteDepartureBoardSnapshot()
            if result.didFail {
                snapshot.phase = .failed
                snapshot.errorMessage = "Favourite departures could not be loaded."
            } else {
                snapshot.phase = .loaded
                snapshot.departures = result.departures.filter {
                    !$0.destination.identifiesSameStation(as: stop.name)
                }
                snapshot.lastUpdated = refreshedAt
                snapshot.errorMessage = nil
                cacheDeparturesForWidget(snapshot.departures, stopId: result.stopId, updatedAt: refreshedAt)
            }
            favouriteDepartureBoards[result.stopId] = snapshot
        }
        isLoadingFavouriteDepartures = false
    }

    func refreshFavouriteDeparture(
        using atpClient: any ATPClient,
        stop: Stop,
        filter: TransitBoardFilter = TransitBoardFilter()
    ) async {
        var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
        snapshot.phase = .loading
        snapshot.errorMessage = nil
        favouriteDepartureBoards[stop.id] = snapshot

        let result = await Self.loadFavouriteDepartureBoard(
            using: atpClient,
            stop: stop,
            filter: filter,
            index: 0
        )
        snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
        if result.didFail {
            snapshot.phase = .failed
            snapshot.errorMessage = "Favourite departures could not be loaded."
        } else {
            snapshot.phase = .loaded
            snapshot.departures = result.departures.filter {
                !$0.destination.identifiesSameStation(as: stop.name)
            }
            snapshot.lastUpdated = .now
            snapshot.errorMessage = nil
            cacheDeparturesForWidget(snapshot.departures, stopId: result.stopId, updatedAt: .now)
        }
        favouriteDepartureBoards[stop.id] = snapshot
    }

    /// Represent unavailable live data explicitly instead of allowing the
    /// injected empty ATP client to look like a confirmed empty departure
    /// board. Existing successful rows remain available, but are marked stale.
    func markFavouriteDeparturesUnavailable(for favourites: [Stop]) {
        isLoadingFavouriteDepartures = false
        for stop in favourites {
            var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
            snapshot.phase = .failed
            snapshot.errorMessage = "Live departures are unavailable in offline mode or without an ATP connection."
            favouriteDepartureBoards[stop.id] = snapshot
        }
    }

    func loadDepartures(using atpClient: any ATPClient) async {
        guard let selectedStop else { return }
        isLoadingDepartures = true
        departuresErrorMessage = nil

        do {
            let refreshedDepartures = try await atpClient.departureBoards(
                stopIds: selectedStop.platformIds,
                options: currentDepartureBoardOptions()
            )
            departures = departuresWithPlatformFallback(
                in: refreshedDepartures,
                from: departures
            ).filter { !$0.destination.identifiesSameStation(as: selectedStop.name) }
            departuresLastUpdated = .now
            cacheDeparturesForWidget(departures, stopId: selectedStop.id, updatedAt: .now)
        } catch {
            // Keep the last successful live board visible while the existing
            // data is marked stale. Clearing it here forces the UI onto the
            // static fallback, which can legitimately have no platform data.
            departuresErrorMessage = "Departures could not be loaded."
        }

        isLoadingDepartures = false
    }

    private func cacheDeparturesForWidget(_ departures: [Departure], stopId: String, updatedAt: Date) {
        let shared = departures.prefix(8).map {
            SharedWidgetDeparture(
                id: $0.id,
                lineName: $0.lineName,
                destination: $0.destination,
                scheduledDeparture: $0.scheduledDeparture,
                realtimeDeparture: $0.realtimeDeparture,
                delayMinutes: $0.delayMinutes,
                platform: $0.platform,
                isCancelled: $0.isCancelled
            )
        }
        SharedTransitDataStore.saveFavouriteDepartureBoard(
            stopId: stopId,
            departures: shared,
            updatedAt: updatedAt
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "DeparturesSummaryWidget")
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

    func updateDepartureBoardFilter(_ filter: TransitBoardFilter) {
        departureBoardFilter = filter
    }

    func resetDepartureBoardFilter() {
        departureBoardFilter = TransitBoardFilter()
    }

    private func currentDepartureBoardOptions() -> ATPDepartureBoardOptions {
        let lines: [String]
        if let selectedDepartureLine,
           let route = selectedStopRoutes.first(where: { $0.id == selectedDepartureLine }) {
            // ATP accepts public line labels. Including the GTFS route id as a
            // second value would cause a strict upstream filter to miss data.
            lines = [route.shortName]
        } else {
            lines = []
        }

        var filter = departureBoardFilter
        if let selectedDeparturePlatform {
            filter.platforms = [selectedDeparturePlatform]
        }
        return filter.options(lines: lines)
    }

    func loadOfflineScheduledDepartures(
        using gtfsService: any GTFSService,
        now: Date = .now
    ) async {
        guard let selectedStop else {
            offlineScheduledDepartures = []
            return
        }

        offlineScheduledDepartures = await gtfsService.scheduledDepartures(
            for: selectedStop,
            now: now,
            limit: 8
        )
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        favouriteDepartureBoards.values.contains { $0.isStale() }
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
