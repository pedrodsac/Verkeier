import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    func scheduleMapRegionUpdate(_ region: MKCoordinateRegion) {
        mapRegionUpdateTask?.cancel()
        mapRegionUpdateTask = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await map.updateVisibleMapRegion(region, using: gtfsService)
        }
    }

    func scheduleSearchUpdate() {
        let query = search.searchQuery
        guard !query.isEmpty else {
            Task {
                await search.searchStops(using: gtfsService)
            }
            return
        }
        searchUpdateContinuation?.yield(query)
    }

    func observeSearchUpdates() async {
        let stream = AsyncStream<String>.makeStream(of: String.self)
        searchUpdateContinuation = stream.continuation
        defer {
            searchUpdateContinuation = nil
        }

        for await query in stream.stream.debounce(for: .milliseconds(250)) {
            guard !Task.isCancelled else { return }
            guard query == search.searchQuery else { continue }
            await search.searchStops(using: gtfsService)
        }
    }

    func scheduleNearbyStopsRefresh() {
        nearbyStopsUpdateTask?.cancel()
        nearbyStopsUpdateTask = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await map.loadNearbyStops(
                location: locationService.currentLocation,
                using: liveTransitService,
                gtfsService: gtfsService,
                walkingRouter: walkingRouter
            )
            await map.loadNearbyStopRoutes(using: gtfsService)
        }
    }

    var sheetActions: TransitSheetActions {
        TransitSheetActions(
            openSpecialEvent: openSpecialEvent,
            favourites: FavouritesActions(
                openStop: { router.show([.stopDetail($0)], detent: .medium) },
                planTo: router.planRoute(to:),
                planFrom: router.planRoute(from:),
                refreshStop: refreshFavouriteStop,
                refreshAll: refreshFavouriteStops,
                updateLabels: updateFavouriteLabels,
                updateAppearance: updateFavouriteAppearance,
                removeFavourite: removeFavourite,
                findStop: router.showSearch
            )
        )
    }

    func openSpecialEvent(_ event: SpecialEvent) {
        Task { @MainActor in
            _ = event
        }
    }

    func refreshFavouriteStop(_ stop: Stop) async {
        await favourites.refreshFavouriteDeparture(
            stop: stop,
            using: liveTransitService,
            gtfsService: gtfsService
        )
    }

    func refreshFavouriteStops() async {
        await favourites.loadFavouriteDepartures(
            favourites: favouriteStops,
            using: liveTransitService,
            gtfsService: gtfsService
        )
    }

    func updateFavouriteLabels(stopID: String, labels: [String]) {
        favourites.updateLabels(stopID: stopID, labels: labels, in: modelContext)
    }

    func updateFavouriteAppearance(stopID: String, label: String, colorHex: String, iconName: String) {
        favourites.updateAppearance(
            stopID: stopID,
            label: label,
            colorHex: colorHex,
            iconName: iconName,
            in: modelContext
        )
    }

    func removeFavourite(stopID: String) {
        favourites.remove(stopID: stopID, in: modelContext)
    }

}
