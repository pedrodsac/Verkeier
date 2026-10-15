import SwiftUI

/// A screen the main sheet can push onto its Home or Plan stack.
enum SheetRoute: Hashable {
    case search
    case stopGroup
    case stopDetail(Stop)
    case directionsForPreset(String)
    case routePlaceSearch(RouteEndpoint)
    case routeTimeline(String)
    case departureTrip(Departure, Stop)
    case tripDetail(TripDetailSelection)
    case lineDetail(TransitRoute)
    case alerts

    var defaultDetent: SheetDetent {
        switch self {
        case .search, .routePlaceSearch, .routeTimeline, .lineDetail, .alerts:
            .expanded
        case .stopGroup, .stopDetail, .directionsForPreset, .tripDetail, .departureTrip:
            .medium
        }
    }

    var navigationTitle: String {
        switch self {
        case .search:
            "Search"
        case .stopGroup:
            "Stops at this location"
        case let .stopDetail(stop):
            stop.displayName
        case .directionsForPreset:
            "Directions"
        case let .routePlaceSearch(endpoint):
            endpoint.searchTitle
        case .routeTimeline:
            "Selected route"
        case let .departureTrip(departure, _):
            departure.lineName
        case let .tripDetail(selection):
            selection.lineName
        case let .lineDetail(route):
            route.shortName.isEmpty ? "Line details" : route.shortName
        case .alerts:
            "Service Alerts"
        }
    }
}

/// The main sheet's tabs.
enum SheetTab: Hashable, CaseIterable {
    case home
    case plan
    case settings
}
