import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func setMapModeFilter(_ mode: TransportMode?) {
        mapModeFilter = mode
    }

    func showHome() {
        sheetContext = .home
        sheetDetent = .medium
        selectedStopGroup = []
        selectedBikeShareStations = []
        clearRoute()
        clearLineDetail()
    }

    func showSearch() {
        sheetContext = .search
        sheetDetent = .expanded
        clearRoute()
        clearLineDetail()
    }

    func showAlerts() {
        sheetContext = .alerts
        sheetDetent = .expanded
        clearRoute()
    }

    func showStopDetail() {
        guard selectedStop != nil else {
            showHome()
            return
        }
        sheetContext = .stopDetail
        sheetDetent = .medium
    }

    func showSettings() {
        sheetContext = .settings
        sheetDetent = .expanded
        clearRoute()
        clearLineDetail()
    }

    func showDirections() {
        guard routeDestination != nil || selectedStop != nil else { return }
        sheetContext = .directions
        sheetDetent = .medium
    }

    func showRouteTimeline() {
        guard selectedRouteOption != nil else { return }
        sheetContext = .routeTimeline
        sheetDetent = .expanded
    }

    func showLineDetail(_ route: TransitRoute) {
        selectedLineDetailRoute = route
        selectedLineDetailDirectionID = nil
        sheetContext = .lineDetail
        sheetDetent = .expanded
    }

    func selectLineDetailDirection(_ directionID: String) {
        selectedLineDetailDirectionID = directionID
    }

}
