import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func loadFavouriteDepartures(favourites: [Stop]) async {
        guard !favourites.isEmpty else {
            favouriteDepartureBoards = [:]
            isLoadingFavouriteDepartures = false
            return
        }

        markFavouriteDeparturesUnavailable(for: favourites)
    }

    func refreshFavouriteDeparture(stop: Stop, filter _: TransitBoardFilter = TransitBoardFilter()) async {
        var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
        snapshot.phase = .failed
        snapshot.errorMessage = "Transit data is currently unavailable."
        favouriteDepartureBoards[stop.id] = snapshot
    }

    /// Represent unavailable live data explicitly instead of treating a
    /// disconnected provider as a confirmed empty departure board.
    func markFavouriteDeparturesUnavailable(for favourites: [Stop]) {
        isLoadingFavouriteDepartures = false
        for stop in favourites {
            var snapshot = favouriteDepartureBoards[stop.id] ?? FavouriteDepartureBoardSnapshot()
            snapshot.phase = .failed
            snapshot.errorMessage = "Transit data is currently unavailable."
            favouriteDepartureBoards[stop.id] = snapshot
        }
    }

    func loadDepartures() async {
        guard selectedStop != nil else { return }
        departures = []
        offlineScheduledDepartures = []
        departuresLastUpdated = nil
        departuresErrorMessage = "Transit data is currently unavailable."
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

    func loadOfflineScheduledDepartures(now _: Date = .now) async {
        offlineScheduledDepartures = []
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }

    var areFavouriteDeparturesStale: Bool {
        favouriteDepartureBoards.values.contains { $0.isStale() }
    }

}
