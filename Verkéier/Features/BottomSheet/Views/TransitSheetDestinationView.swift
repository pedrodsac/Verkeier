import SwiftUI

/// Maps each sheet route to its screen, for the Home and Plan navigation stacks.
/// ``SheetRouter`` prepares the feature models when a route is shown.
struct TransitSheetDestinationView: View {
    let route: TransitSheetRoute
    var searchContentTopPadding: CGFloat = 0

    var body: some View {
        switch route {
        case .search:
            SearchResultsContent()
                .safeAreaPadding(.horizontal, 16)
                .padding(.top, searchContentTopPadding)
        case .stopGroup:
            StopGroupView()
        case let .stopDetail(stop):
            StopDetailView(stop: stop)
        case .directionsForPreset:
            RoutePlannerScreen(context: .commute)
        case let .routePlaceSearch(endpoint):
            RoutePlaceSearchView(endpoint: endpoint)
        case .routeTimeline:
            RouteTimelineView()
        case let .departureTrip(departure, stop):
            DepartureTripDestination(departure: departure, stop: stop)
        case let .tripDetail(selection):
            TripDetailView(selection: selection)
        case let .lineDetail(route):
            LineDetailView(route: route)
        case .alerts:
            AlertsView()
        }
    }
}
