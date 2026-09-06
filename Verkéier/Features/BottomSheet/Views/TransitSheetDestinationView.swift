import SwiftUI

/// Shared detail destinations used by Home, Favourites, and Plan navigation
/// stacks. Data loading remains coordinated by `TransitSheetRouteActivationCoordinator`.
struct TransitSheetDestinationView: View {
    let route: TransitSheetRoute
    @Binding var searchQuery: String
    var searchContentTopPadding: CGFloat = 0
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

    var body: some View {
        switch route {
        case .search:
            SearchView(
                query: $searchQuery,
                viewModel: viewModel.search,
                actions: SearchActions(from: actions)
            )
            .safeAreaPadding(.horizontal, 16)
            .padding(.top, searchContentTopPadding)
        case .stopGroup:
            ScrollView {
                StopGroupView(viewModel: viewModel.stopGroup)
                    .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

        case .stopDetail:
            ScrollView {
                StopDetailView(
                    viewModel: viewModel.stopDetail,
                    actions: StopDetailActions(from: actions)
                )
                .safeAreaPadding(.horizontal, 16)
            }
            .refreshable { await actions.refreshDepartures() }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let isFavourite = viewModel.stopDetail.isFavourite
                    Button(action: actions.toggleFavourite) {
                        Label(
                            isFavourite ? "Remove favourite" : "Save favourite",
                            systemImage: isFavourite ? "star.fill" : "star"
                        )
                    }
                    .tint(isFavourite ? .yellow : nil)
                }
            }

        case .directions, .directionsForPreset:
            ScrollView {
                RouteView(
                    viewModel: viewModel.route,
                    actions: RouteActions(from: actions)
                )
                .safeAreaPadding(.horizontal, 16)
            }
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
                    viewModel: viewModel.route,
                    openInAppleMaps: actions.openRouteInAppleMaps
                )
                .safeAreaPadding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

        case .lineDetail:
            LineDetailView(
                viewModel: viewModel.lineDetail,
                actions: LineDetailActions(from: actions)
            )
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

        case .alerts:
            ScrollView {
                AlertsView(viewModel: viewModel.alerts)
                    .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: actions.refreshAlerts) {
                        Label("Refresh alerts", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.alerts.isLoading)
                }
            }
        }
    }
}
