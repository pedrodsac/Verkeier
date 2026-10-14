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

    func refreshFavouriteStops() async {
        await favourites.loadFavouriteDepartures(
            favourites: favouriteStops,
            using: liveTransitService,
            gtfsService: gtfsService
        )
    }
}
