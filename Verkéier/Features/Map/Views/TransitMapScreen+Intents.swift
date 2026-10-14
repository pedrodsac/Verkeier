import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    func updateTrackedDepartureIfNeeded() async {
        if let trackedDeparture = DepartureTrackingSelection.trackedDeparture(
            in: stopDetail.departures,
            trackedDepartureId: liveActivityManager.trackedDepartureId
        ) {
            await liveActivityManager.updateTracking(departure: trackedDeparture)
        }

        if let reminderDepartureID = departureReminderService.activeReminder?.departureId,
            let reminderDeparture = stopDetail.departures.first(where: { $0.id == reminderDepartureID })
        {
            await departureReminderService.syncTrackedDeparture(
                reminderDeparture,
                stopName: stopDetail.selectedStop?.name
            )
        }
    }

    func trackNextDeparture(for stop: Stop) {
        Task {
            await stopDetail.loadDepartures(
                using: liveTransitService,
                gtfsService: gtfsService
            )
            guard
                let departure = DepartureTrackingSelection.nextTrackableDeparture(
                    from: stopDetail.departures
                )
            else {
                return
            }
            await liveActivityManager.startTracking(departure: departure, stop: stop)
        }
    }

    func isFavourite(_ stop: Stop) -> Bool {
        favouriteEntities.contains { $0.stopId == stop.id }
    }

    func toggleSelectedFavourite() {
        guard let selectedStop = stopDetail.selectedStop else { return }

        if let existing = favouriteEntities.first(where: { $0.stopId == selectedStop.id }) {
            removeFavourite(stopID: existing.stopId)
        }
    }

    func saveFavouriteCustomization(
        stop: Stop,
        label: String,
        colorHex: String,
        iconName: String
    ) {
        let favourite =
            favouriteEntities.first(where: { $0.stopId == stop.id })
            ?? PersistedFavouriteStop(stop: stop, boardFilter: stopDetail.departureBoardFilter)
        if !favouriteEntities.contains(where: { $0.stopId == stop.id }) {
            modelContext.insert(favourite)
        }
        favourite.displayLabel = label
        favourite.colorHex = colorHex
        favourite.iconName = iconName
        try? modelContext.save()
        mirrorFavouriteEntitiesForIntents()
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
            router.showSearch()
            return
        }

        router.show([.stopDetail(stop)], detent: .expanded)
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
            router.showHome()
        case let .openFavouriteStop(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                router.selectStop(favourite)
                router.show([.stopDetail(favourite)], detent: .expanded)
            } else {
                router.showSearch()
            }
        case let .trackNextDeparture(stopId):
            if let favourite = favouriteEntities.first(where: { $0.stopId == stopId })?.stop {
                router.selectStop(favourite)
                router.show([.stopDetail(favourite)], detent: .expanded)
                trackNextDeparture(for: favourite)
            } else {
                router.showSearch()
            }
        case let .planRoute(destinationName):
            search.searchQuery = destinationName
            Task {
                await search.searchStops(using: gtfsService)
                if let stop = confidentRouteDestinationMatch(for: destinationName) {
                    router.selectStop(stop)
                    Task { await map.loadGTFSMapStops(using: gtfsService) }
                    router.showPlanTab()
                } else {
                    router.showSearch()
                }
            }
        }
    }

    func confidentRouteDestinationMatch(for destinationName: String) -> Stop? {
        let normalizedDestination = destinationName.normalizedForSearch
        let exactMatches = search.searchResults.filter {
            $0.name.normalizedForSearch == normalizedDestination
        }

        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        return search.searchResults.count == 1 ? search.searchResults[0] : nil
    }
}
