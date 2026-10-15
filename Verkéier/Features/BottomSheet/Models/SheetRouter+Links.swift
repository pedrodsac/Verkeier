import Foundation

/// Opens what Siri, Shortcuts, widgets, deep links and Spotlight ask for.
extension SheetRouter {
    func handle(
        _ handoff: TransitIntentHandoff,
        liveTransitService: any LiveTransitService,
        liveActivityManager: LiveActivityManager
    ) {
        switch handoff {
        case .showNearbyStops:
            showHome()
        case let .openFavouriteStop(stopId):
            openFavouriteStop(id: stopId)
        case let .trackNextDeparture(stopId):
            guard let stop = openFavouriteStop(id: stopId) else { return }
            Task {
                await models.stopDetail.trackNextDeparture(
                    from: stop,
                    using: liveTransitService,
                    gtfsService: gtfsService,
                    liveActivityManager: liveActivityManager
                )
            }
        case let .planRoute(destinationName):
            planRoute(toPlaceNamed: destinationName)
        }
    }

    /// Opens a favourite's departures, or search when it is no longer saved.
    @discardableResult
    private func openFavouriteStop(id stopId: String) -> Stop? {
        guard let stop = models.favourites.favouriteStops.first(where: { $0.id == stopId }) else {
            showSearch()
            return nil
        }
        selectStop(stop)
        show([.stopDetail(stop)], detent: .expanded)
        return stop
    }

    /// Plans a route to the stop a spoken place name clearly refers to, or
    /// shows the search results to pick from.
    private func planRoute(toPlaceNamed name: String) {
        let search = models.search
        search.searchQuery = name
        Task {
            await search.searchStops(using: gtfsService)
            if let stop = search.confidentMatch(for: name) {
                selectStop(stop)
                Task { await models.map.loadGTFSMapStops(using: gtfsService) }
                showPlanTab()
            } else {
                showSearch()
            }
        }
    }
}
