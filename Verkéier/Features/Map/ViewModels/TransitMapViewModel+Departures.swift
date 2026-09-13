import CoreLocation
import MapKit
import Observation
import SwiftUI
import WidgetKit

extension TransitMapViewModel {
    func loadFavouriteDepartures(
        favourites: [Stop],
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService
    ) async {
        guard !favourites.isEmpty else {
            favouriteDepartureBoards = [:]
            isLoadingFavouriteDepartures = false
            return
        }

        isLoadingFavouriteDepartures = true
        await withTaskGroup(of: FavouriteDepartureBoardResult.self) { group in
            for (index, stop) in favourites.enumerated() {
                group.addTask {
                    let boardStop = await liveTransitService.resolvedStop(
                        for: stop,
                        gtfsService: gtfsService
                    )
                    let scheduled = await gtfsService.scheduledDepartures(for: boardStop, at: .now, limit: 10)
                    do {
                        let live = try await liveTransitService.departureBoard(for: boardStop, filter: TransitBoardFilter())
                        return FavouriteDepartureBoardResult(
                            stopId: stop.id,
                            departures: live,
                            didFail: false,
                            usedLiveData: true,
                            index: index
                        )
                    } catch {
                        let fallback = scheduled.map { $0.asDeparture(stopID: stop.id) }
                        return FavouriteDepartureBoardResult(
                            stopId: stop.id,
                            departures: fallback,
                            didFail: fallback.isEmpty,
                            usedLiveData: false,
                            index: index
                        )
                    }
                }
            }
            var results: [FavouriteDepartureBoardResult] = []
            for await value in group { results.append(value) }
            for result in results.sorted(by: { $0.index < $1.index }) {
                var snapshot = FavouriteDepartureBoardSnapshot()
                snapshot.departures = result.departures
                snapshot.lastUpdated = .now
                snapshot.phase = result.didFail ? .failed : .loaded
                snapshot.errorMessage = result.didFail ? "Departures could not be refreshed." : nil
                favouriteDepartureBoards[result.stopId] = snapshot
                saveFavouriteDepartureBoard(stopID: result.stopId, snapshot: snapshot)
            }
            if results.contains(where: \ .usedLiveData) {
                liveTransitLastUpdated = .now
                liveTransitErrorMessage = nil
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "DeparturesSummaryWidget")
        isLoadingFavouriteDepartures = false
    }

    func refreshFavouriteDeparture(
        stop: Stop,
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService,
        filter: TransitBoardFilter = TransitBoardFilter()
    ) async {
        var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
        snapshot.phase = .loading
        snapshot.errorMessage = nil
        favouriteDepartureBoards[stop.id] = snapshot
        let boardStop = await liveTransitService.resolvedStop(for: stop, gtfsService: gtfsService)
        let scheduled = await gtfsService.scheduledDepartures(for: boardStop, at: .now, limit: 10)
        do {
            snapshot.departures = try await liveTransitService.departureBoard(for: boardStop, filter: filter)
            snapshot.phase = .loaded
            snapshot.lastUpdated = .now
            liveTransitLastUpdated = .now
            liveTransitErrorMessage = nil
        } catch {
            snapshot.departures = scheduled.map { $0.asDeparture(stopID: stop.id) }
            snapshot.phase = snapshot.departures.isEmpty ? .failed : .loaded
            snapshot.lastUpdated = .now
            snapshot.errorMessage = snapshot.departures.isEmpty ? "Departures could not be refreshed." : nil
            liveTransitErrorMessage = error.localizedDescription
        }
        favouriteDepartureBoards[stop.id] = snapshot
        saveFavouriteDepartureBoard(stopID: stop.id, snapshot: snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "DeparturesSummaryWidget")
    }

    /// Preserve the failed state when neither source has produced a board.
    func markFavouriteDeparturesUnavailable(for favourites: [Stop]) {
        isLoadingFavouriteDepartures = false
        for stop in favourites {
            var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
            snapshot.phase = .failed
            snapshot.errorMessage = "No live or scheduled departures could be refreshed."
            favouriteDepartureBoards[stop.id] = snapshot
        }
    }

    func loadDepartures(
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService
    ) async {
        guard let selectedStop else { return }
        let boardStop = await liveTransitService.resolvedStop(
            for: selectedStop,
            gtfsService: gtfsService
        )
        if boardStop != selectedStop {
            self.selectedStop = boardStop
        }
        isLoadingDepartures = true
        departures = []
        offlineScheduledDepartures = await gtfsService.scheduledDepartures(
            for: boardStop,
            at: .now,
            limit: departureBoardFilter.maximumJourneys
        )
        departuresLastUpdated = nil
        departuresErrorMessage = nil
        do {
            departures = try await liveTransitService.departureBoard(for: boardStop, filter: departureBoardFilter)
            departuresLastUpdated = .now
            liveTransitLastUpdated = .now
            liveTransitErrorMessage = nil
        } catch {
            liveTransitErrorMessage = error.localizedDescription
            if offlineScheduledDepartures.isEmpty {
                departuresErrorMessage = "No live or scheduled departures are available for this stop."
            }
        }
        rebuildDepartureFilters()
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

    func updateDepartureBoardFilter(_ filter: TransitBoardFilter) {
        departureBoardFilter = filter
    }

    func resetDepartureBoardFilter() {
        departureBoardFilter = TransitBoardFilter()
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
            at: now,
            limit: departureBoardFilter.maximumJourneys
        )
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        favouriteDepartureBoards.values.contains { $0.isStale() }
    }

}

private extension TransitMapViewModel {
    func saveFavouriteDepartureBoard(
        stopID: String,
        snapshot: FavouriteDepartureBoardSnapshot
    ) {
        guard let updatedAt = snapshot.lastUpdated else { return }
        let sources = Array(Set(snapshot.departures.map { $0.dataSource.displayName }))
            .sorted()
        SharedTransitDataStore.saveFavouriteDepartureBoard(
            stopId: stopID,
            departures: snapshot.departures.map { departure in
                SharedWidgetDeparture(
                    id: departure.id,
                    lineName: departure.lineName,
                    destination: departure.destination,
                    scheduledDeparture: departure.scheduledDeparture,
                    realtimeDeparture: departure.realtimeDeparture,
                    delayMinutes: departure.delayMinutes,
                    platform: departure.platform,
                    isCancelled: departure.isCancelled,
                    sourceLabel: departure.dataSource.displayName
                )
            },
            updatedAt: updatedAt,
            sourceSummary: sources.isEmpty ? nil : sources.joined(separator: " + ")
        )
    }
}

private extension OfflineScheduleDeparture {
    nonisolated func asDeparture(stopID: String) -> Departure {
        Departure(
            id: id,
            stopId: stopID,
            lineName: lineName,
            destination: destination,
            scheduledDeparture: departureDate,
            platform: platform,
            dataSource: .gtfs
        )
    }
}
