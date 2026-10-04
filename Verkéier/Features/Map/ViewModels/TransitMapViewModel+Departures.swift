import CoreLocation
import MapKit
import Observation
import SwiftUI
import WidgetKit

extension TransitMapViewModel {
    /// Cache only board inputs. Location fixes, route results, and loading-state
    /// changes must not repeat departure normalization and sorting.
    var departureBoardPresentation: StopDepartureBoardPresentation {
        departureBoardCache.presentation(for: .init(
            stopID: selectedStop?.id ?? "",
            routes: selectedStopRoutes,
            liveDepartures: departures,
            scheduledDepartures: offlineScheduledDepartures,
            useScheduledFallback: isUsingOfflineDepartures,
            selectedLine: selectedDepartureLine,
            selectedPlatform: selectedDeparturePlatform
        ))
    }

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
                    do {
                        let live = try await liveTransitService.departureBoardSnapshot(for: boardStop, filter: TransitBoardFilter())
                        return FavouriteDepartureBoardResult(
                            stopId: stop.id,
                            departures: live.departures,
                            fetchedAt: live.fetchedAt,
                            didFail: false,
                            usedLiveData: true,
                            index: index
                        )
                    } catch {
                        let scheduled = await gtfsService.scheduledDepartures(for: boardStop, at: .now, limit: .max)
                        let fallback = scheduled.map { $0.asDeparture(stopID: stop.id) }
                        return FavouriteDepartureBoardResult(
                            stopId: stop.id,
                            departures: fallback,
                            fetchedAt: .now,
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
                snapshot.lastUpdated = result.fetchedAt
                snapshot.phase = result.didFail ? .failed : .loaded
                snapshot.errorMessage = result.didFail ? "Departures could not be refreshed." : nil
                favouriteDepartureBoards[result.stopId] = snapshot
                saveFavouriteDepartureBoard(stopID: result.stopId, snapshot: snapshot)
            }
            if results.contains(where: \ .usedLiveData) {
                liveTransitLastUpdated = results.filter(\.usedLiveData).map(\.fetchedAt).min()
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
        do {
            let board = try await liveTransitService.departureBoardSnapshot(for: boardStop, filter: filter)
            snapshot.departures = board.departures
            snapshot.phase = .loaded
            snapshot.lastUpdated = board.fetchedAt
            liveTransitLastUpdated = board.fetchedAt
            liveTransitErrorMessage = nil
        } catch {
            let scheduled = await gtfsService.scheduledDepartures(for: boardStop, at: .now, limit: .max)
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
        let selectedStopID = selectedStop.id
        departureLoadGeneration &+= 1
        let requestGeneration = departureLoadGeneration
        isLoadingDepartures = true
        departuresErrorMessage = nil
        isUsingOfflineDepartures = false

        let boardStop = await liveTransitService.resolvedStop(
            for: selectedStop,
            gtfsService: gtfsService
        )
        guard !Task.isCancelled else {
            if isCurrentDepartureRequest(requestGeneration, for: selectedStopID) {
                isLoadingDepartures = false
            }
            return
        }
        guard isCurrentDepartureRequest(requestGeneration, for: selectedStopID) else { return }
        if boardStop != selectedStop {
            self.selectedStop = boardStop
        }

        let liveDepartures: [Departure]
        let fetchedAt: Date?
        let scheduledDepartures: [OfflineScheduleDeparture]
        let liveError: Error?
        do {
            let board = try await liveTransitService.departureBoardSnapshot(
                for: boardStop,
                filter: departureBoardFilter
            )
            liveDepartures = board.departures
            fetchedAt = board.fetchedAt
            scheduledDepartures = []
            liveError = nil
        } catch {
            liveDepartures = []
            fetchedAt = nil
            scheduledDepartures = await gtfsService.scheduledDepartures(
                for: boardStop,
                at: now(),
                limit: .max
            )
            liveError = error
        }

        guard !Task.isCancelled else {
            if isCurrentDepartureRequest(requestGeneration, for: boardStop.id) {
                isLoadingDepartures = false
            }
            return
        }
        guard isCurrentDepartureRequest(requestGeneration, for: boardStop.id) else { return }

        departures = liveDepartures
        offlineScheduledDepartures = scheduledDepartures
        isUsingOfflineDepartures = liveError != nil
        departuresLastUpdated = fetchedAt
        liveTransitLastUpdated = fetchedAt ?? liveTransitLastUpdated
        liveTransitErrorMessage = liveError?.localizedDescription
        departuresErrorMessage = liveError != nil && scheduledDepartures.isEmpty
            ? "No live or offline departures are available for this stop."
            : nil
        isLoadingDepartures = false
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        if selectedDepartureLine == route.id {
            selectedDepartureLine = nil
        } else {
            selectedDepartureLine = route.id
        }

        selectedDeparturePlatform = nil
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
        let scheduledDepartures = await gtfsService.scheduledDepartures(
            for: selectedStop,
            at: now,
            limit: .max
        )
        guard self.selectedStop?.id == selectedStop.id else { return }
        offlineScheduledDepartures = scheduledDepartures
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        favouriteDepartureBoards.values.contains { $0.isStale() }
    }

    private func isCurrentDepartureRequest(_ generation: Int, for stopID: String) -> Bool {
        departureLoadGeneration == generation && selectedStop?.id == stopID
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
