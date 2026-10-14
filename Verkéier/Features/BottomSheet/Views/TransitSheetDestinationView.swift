import SwiftUI

/// Maps each sheet route to its screen, for the Home and Plan navigation stacks.
/// ``SheetRouter`` prepares the feature models when a route is shown.
struct TransitSheetDestinationView: View {
    let route: TransitSheetRoute
    var searchContentTopPadding: CGFloat = 0
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

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

        case .directions, .directionsForPreset:
            ScrollView {
                RouteView(
                    viewModel: viewModel.route,
                    actions: RouteActions(from: actions)
                )
                .safeAreaPadding(.horizontal, 16)
            }
            .refreshable { await actions.refreshRoutes() }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RoutePlanningTimeButton(
                        current: viewModel.route.planningTime,
                        onChange: actions.setRoutePlanningTime
                    )
                }
            }

        case let .routePlaceSearch(endpoint):
            RoutePlaceSearchView(
                endpoint: endpoint,
                viewModel: viewModel.route
            ) { place in
                switch endpoint {
                case .origin:
                    actions.selectRouteOrigin(place)
                case .destination:
                    guard let place else { return }
                    actions.selectRouteDestination(place)
                }
            }

        case .routeTimeline:
            ScrollView {
                RouteTimelineView(
                    viewModel: viewModel.route
                )
                .safeAreaPadding(.horizontal, 16)
            }
            .refreshable { await actions.refreshRouteRealtime() }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

        case let .departureTrip(departure, stop):
            DepartureTripDestination(departure: departure, stop: stop)

        case let .tripDetail(selection):
            if let model = viewModel.tripDetail {
                TripDetailView(selection: selection, viewModel: model, refresh: actions.refreshTripDetail)
            }

        case .lineDetail:
            LineDetailView(
                viewModel: viewModel.lineDetail,
                actions: LineDetailActions(from: actions)
            )
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

        case .alerts:
            AlertsView()
        }
    }
}
