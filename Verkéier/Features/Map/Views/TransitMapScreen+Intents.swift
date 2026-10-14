import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
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
