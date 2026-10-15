import Foundation
import Observation
import SwiftData
import WidgetKit

/// Departure boards for the rider's favourite stops, mirrored to the widget.
@MainActor @Observable
final class FavouritesModel {
    /// The saved favourite stops, mirrored from SwiftData by the map screen
    /// through ``savedFavouritesDidChange(_:in:)``.
    var favouriteStops: [Stop] = []
    var favouriteDepartureBoards: [String: FavouriteDepartureBoardSnapshot] = [:]
    /// Favourites can always fall back to a timetable board once the GTFS feed
    /// is ready, even without the live relay.
    var gtfsFeedStatus: GTFSFeedStatus = .unavailable

    var favouriteStopIDs: Set<String> {
        Set(favouriteStops.map(\.id))
    }

    /// Re-checks the timetable feed, downloading a newer one when needed or forced.
    func refreshFeedStatus(using gtfsService: any GTFSService, force: Bool = false) async {
        gtfsFeedStatus = await gtfsService.refreshIfNeeded(force: force)
    }

    /// Refreshes the boards now and every 45 seconds until the task is cancelled.
    func keepBoardsCurrent(
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService
    ) async {
        await loadFavouriteDepartures(favourites: favouriteStops, using: liveTransitService, gtfsService: gtfsService)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            await loadFavouriteDepartures(
                favourites: favouriteStops,
                using: liveTransitService,
                gtfsService: gtfsService
            )
        }
    }

    func loadFavouriteDepartures(
        favourites: [Stop],
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService
    ) async {
        guard !favourites.isEmpty else {
            favouriteDepartureBoards = [:]
            return
        }

        await withTaskGroup(of: FavouriteDepartureBoardResult.self) { group in
            for (index, stop) in favourites.enumerated() {
                group.addTask {
                    let boardStop = await liveTransitService.resolvedStop(
                        for: stop,
                        gtfsService: gtfsService
                    )
                    do {
                        let live = try await liveTransitService.departureBoardSnapshot(
                            for: boardStop,
                            filter: TransitBoardFilter()
                        )
                        return FavouriteDepartureBoardResult(
                            stopId: stop.id,
                            departures: live.departures,
                            fetchedAt: live.fetchedAt,
                            didFail: false,
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
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "DeparturesSummaryWidget")
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
        } catch {
            let scheduled = await gtfsService.scheduledDepartures(for: boardStop, at: .now, limit: .max)
            snapshot.departures = scheduled.map { $0.asDeparture(stopID: stop.id) }
            snapshot.phase = snapshot.departures.isEmpty ? .failed : .loaded
            snapshot.lastUpdated = .now
            snapshot.errorMessage = snapshot.departures.isEmpty ? "Departures could not be refreshed." : nil
        }
        favouriteDepartureBoards[stop.id] = snapshot
        saveFavouriteDepartureBoard(stopID: stop.id, snapshot: snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "DeparturesSummaryWidget")
    }

    /// Drops boards for stops that are no longer favourites.
    private func retainBoards(forStopIDs stopIDs: Set<String>) {
        favouriteDepartureBoards = favouriteDepartureBoards.filter { stopIDs.contains($0.key) }
    }

    func removeBoard(forStopID stopID: String) {
        favouriteDepartureBoards.removeValue(forKey: stopID)
        SharedTransitDataStore.removeFavouriteDepartureBoard(stopId: stopID)
    }
}

// MARK: - Saved favourites

extension FavouritesModel {
    /// Takes the saved favourites from SwiftData, drops boards for removed
    /// ones, and mirrors them to App Intents and Spotlight.
    func savedFavouritesDidChange(_ stops: [Stop], in context: ModelContext) {
        favouriteStops = stops
        retainBoards(forStopIDs: favouriteStopIDs)
        mirrorForIntents(in: context)
    }

    func isFavourite(_ stop: Stop) -> Bool {
        favouriteStops.contains { $0.id == stop.id }
    }

    /// Saves `stop` as a favourite, or updates the label and look of an existing one.
    func save(
        _ stop: Stop,
        label: String,
        colorHex: String,
        iconName: String,
        boardFilter: TransitBoardFilter,
        in context: ModelContext
    ) {
        let favourite =
            Self.favourite(stopID: stop.id, in: context)
            ?? {
                let favourite = PersistedFavouriteStop(stop: stop, boardFilter: boardFilter)
                context.insert(favourite)
                return favourite
            }()
        favourite.displayLabel = label
        favourite.colorHex = colorHex
        favourite.iconName = iconName
        saveChanges(in: context)
    }

    func updateAppearance(stopID: String, label: String, colorHex: String, iconName: String, in context: ModelContext) {
        guard let favourite = Self.favourite(stopID: stopID, in: context) else { return }
        favourite.displayLabel = label
        favourite.colorHex = colorHex
        favourite.iconName = iconName
        saveChanges(in: context)
    }

    func remove(stopID: String, in context: ModelContext) {
        guard let favourite = Self.favourite(stopID: stopID, in: context) else { return }
        context.delete(favourite)
        removeBoard(forStopID: stopID)
        saveChanges(in: context)
    }

    /// Mirrors the saved favourites to App Intents and Spotlight.
    private func mirrorForIntents(in context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedFavouriteStop>(sortBy: [SortDescriptor(\.createdAt)])
        let favourites = (try? context.fetch(descriptor)) ?? []
        FavouriteStopEntityStore.save(favourites: favourites)
        if favourites.isEmpty {
            FavouriteStopSpotlightIndexer.removeAll()
        } else {
            FavouriteStopSpotlightIndexer.index(favourites.map(\.stop))
        }
    }

    private func saveChanges(in context: ModelContext) {
        try? context.save()
        mirrorForIntents(in: context)
    }

    private static func favourite(stopID: String, in context: ModelContext) -> PersistedFavouriteStop? {
        let descriptor = FetchDescriptor<PersistedFavouriteStop>(predicate: #Predicate { $0.stopId == stopID })
        return try? context.fetch(descriptor).first
    }
}

private extension FavouritesModel {
    struct FavouriteDepartureBoardResult: Sendable {
        let stopId: String
        let departures: [Departure]
        let fetchedAt: Date
        let didFail: Bool
        let index: Int
    }

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
