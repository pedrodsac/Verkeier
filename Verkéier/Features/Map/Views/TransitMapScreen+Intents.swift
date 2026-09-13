import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    func updateTrackedDepartureIfNeeded() async {
        if let trackedDeparture = DepartureTrackingSelection.trackedDeparture(
            in: viewModel.departures,
            trackedDepartureId: liveActivityManager.trackedDepartureId
        ) {
            await liveActivityManager.updateTracking(departure: trackedDeparture)
        }

        if let reminderDepartureID = departureReminderService.activeReminder?.departureId,
           let reminderDeparture = viewModel.departures.first(where: { $0.id == reminderDepartureID }) {
            await departureReminderService.syncTrackedDeparture(
                reminderDeparture,
                stopName: viewModel.selectedStop?.name
            )
        }
    }

    func trackNextDeparture(for stop: Stop) {
        Task {
            await viewModel.loadDepartures(
                using: liveTransitService,
                gtfsService: gtfsService
            )
            guard let departure = DepartureTrackingSelection.nextTrackableDeparture(
                from: viewModel.departures
            ) else {
                return
            }
            await liveActivityManager.startTracking(departure: departure, stop: stop)
        }
    }

    func isFavourite(_ stop: Stop) -> Bool {
        favouriteEntities.contains { $0.stopId == stop.id }
    }

    func toggleSelectedFavourite() {
        guard let selectedStop = viewModel.selectedStop else { return }

        if let existing = favouriteEntities.first(where: { $0.stopId == selectedStop.id }) {
            removeFavourite(stopID: existing.stopId)
        } else {
            modelContext.insert(PersistedFavouriteStop(
                stop: selectedStop,
                boardFilter: viewModel.departureBoardFilter
            ))
            try? modelContext.save()
            mirrorFavouriteEntitiesForIntents()
        }
    }

    func mirrorFavouriteEntitiesForIntents() {
        let favourites = favouriteEntities
        FavouriteStopEntityStore.save(favourites: favourites)
        if favourites.isEmpty {
            FavouriteStopSpotlightIndexer.removeAll()
        } else {
            FavouriteStopSpotlightIndexer.index(favourites.map(\.stop))
        }
    }

    func handlePendingIntentHandoff() {
        guard let handoff = TransitIntentHandoff.consumePending() else { return }
        handle(handoff)
    }

    func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("stop.")
        else {
            return
        }

        let stopId = String(identifier.dropFirst("stop.".count))
        guard let stop = favouriteEntities.first(where: { $0.stopId == stopId })?.stop else {
            showSearch()
            return
        }

        navigateToSheet([.stopDetail(stop)], detent: .expanded)
    }

    func handleDeepLink(_ url: URL) {
        guard let deepLink = TransitDeepLink(url: url),
              let handoff = TransitIntentHandoff(deepLink)
        else {
            return
        }

        handle(handoff)
    }

    func handle(_ handoff: TransitIntentHandoff) {
        switch handoff {
        case .showNearbyStops:
            showHome()
        case let .openFavouriteStop(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                viewModel.selectStop(favourite)
                navigateToSheet([.stopDetail(favourite)], detent: .expanded)
            } else {
                showSearch()
            }
        case let .trackNextDeparture(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                viewModel.selectStop(favourite)
                navigateToSheet([.stopDetail(favourite)], detent: .expanded)
                trackNextDeparture(for: favourite)
            } else {
                showSearch()
            }
        case let .planRoute(destinationName):
            viewModel.searchQuery = destinationName
            Task {
                await viewModel.searchStops(using: gtfsService)
                if let stop = confidentRouteDestinationMatch(for: destinationName) {
                    viewModel.selectStop(stop)
                    loadSelectedStopData()
                    showPlanTab()
                } else {
                    showSearch()
                }
            }
        }
    }

    func confidentRouteDestinationMatch(for destinationName: String) -> Stop? {
        let normalizedDestination = destinationName.normalizedForSearch
        let exactMatches = viewModel.searchResults.filter {
            $0.name.normalizedForSearch == normalizedDestination
        }

        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        return viewModel.searchResults.count == 1 ? viewModel.searchResults[0] : nil
    }
}
