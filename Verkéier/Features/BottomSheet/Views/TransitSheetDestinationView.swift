import SwiftUI

/// Shared detail destinations used by Home, Favourites, and Plan navigation
/// stacks. Data loading remains coordinated by `TransitSheetRouteActivationCoordinator`.
struct TransitSheetDestinationView: View {
    let route: TransitSheetRoute
    @Binding var searchQuery: String
    var searchContentTopPadding: CGFloat = 0
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions
    @State private var favouriteCustomization: FavouriteCustomizationDraft?

    var body: some View {
        switch route {
        case .search:
			SearchResultsContent(
				query: $searchQuery,
				viewModel: viewModel.search,
				actions: SearchActions(from: actions)
			)
            .safeAreaPadding(.horizontal, 16)
            .padding(.top, searchContentTopPadding)
        case .stopGroup:
			StopGroupView(viewModel: viewModel.stopGroup)
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
        case .stopDetail:
            StopDetailView(
                viewModel: viewModel.stopDetail,
                actions: StopDetailActions(from: actions)
            )
            .refreshable { await actions.refreshDepartures() }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if let stop = viewModel.stopDetail.stop,
                   !viewModel.stopDetail.displayedDepartures.isEmpty {
                    ToolbarTitleMenu {
                        ShareLink(
                            item: stopDeparturesShareText(
                                stop: stop,
                                departures: viewModel.stopDetail.displayedDepartures
                            )
                        ) {
                            Label("Share next departures", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let isFavourite = viewModel.stopDetail.isFavourite
                    Button {
                        if isFavourite {
                            actions.toggleFavourite()
                        } else if let stop = viewModel.stopDetail.stop {
                            favouriteCustomization = FavouriteCustomizationDraft(stop: stop)
                        }
                    } label: {
                        Label(
                            isFavourite ? "Remove favourite" : "Save favourite",
                            systemImage: isFavourite ? "star.fill" : "star"
                        )
                    }
                    .tint(isFavourite ? .yellow : nil)
                }
            }
            .sheet(item: $favouriteCustomization) { draft in
                FavouriteCustomizerView(
                    stop: draft.stop,
                    initialLabel: draft.label,
                    initialColorHex: draft.colorHex,
                    initialIconName: draft.iconName
                ) { label, colorHex, iconName in
                    actions.saveFavouriteCustomization(draft.stop, label, colorHex, iconName)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                    viewModel: viewModel.route
                )
                .safeAreaPadding(.horizontal, 16)
            }
            .refreshable { await actions.refreshRouteRealtime() }
            .navigationTitle(route.navigationTitle)
            .toolbarTitleDisplayMode(.inline)

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

    /// Formats the next five departures as a shareable plain-text message.
    private func stopDeparturesShareText(stop: Stop, departures: [Departure]) -> String {
        var lines = ["Next departures — \(stop.name)"]
        for departure in departures.prefix(5) {
            let time = (departure.realtimeDeparture ?? departure.scheduledDeparture)?
                .formatted(date: .omitted, time: .shortened) ?? "--:--"
            let status = if departure.isCancelled {
                " (cancelled)"
            } else if let delay = departure.delayMinutes, delay > 0 {
                " (+\(delay) min)"
            } else {
                ""
            }
            lines.append("\(time)  \(departure.lineName) → \(departure.destination)\(status)")
        }
        lines.append("via Verkéier")
        return lines.joined(separator: "\n")
    }
}
