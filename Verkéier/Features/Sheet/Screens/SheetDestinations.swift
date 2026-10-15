import SwiftUI

/// Maps each sheet route to its screen, for the Home and Plan navigation stacks.
/// ``SheetRouter`` prepares the feature models when a route is shown.
struct SheetDestinations: View {
    let route: SheetRoute
    var searchContentTopPadding: CGFloat = 0

    var body: some View {
        switch route {
        case .search:
            SearchScreen()
                .safeAreaPadding(.horizontal, 16)
                .padding(.top, searchContentTopPadding)
        case .stopGroup:
            StopGroupScreen()
        case let .stopDetail(stop):
            StopDetailScreen(stop: stop)
        case .directionsForPreset:
            RoutePlannerScreen(context: .commute)
        case let .routePlaceSearch(endpoint):
            PlaceSearchScreen(endpoint: endpoint)
        case .routeTimeline:
            RouteTimelineScreen()
        case let .departureTrip(departure, stop):
            DepartureTripScreen(departure: departure, stop: stop)
        case let .tripDetail(selection):
            TripDetailScreen(selection: selection)
        case let .lineDetail(route):
            LineDetailScreen(route: route)
        case .alerts:
            AlertsScreen()
        }
    }
}
