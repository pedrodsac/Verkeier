import SwiftUI

struct BottomSheetContent: View {
    let viewModel: TransitSheetPresentationModel
    @Binding var searchQuery: String
    let actions: TransitSheetActions

    var body: some View {
        Group {
            switch viewModel.context {
            case .home:
                CommuteDashboardView(
                    viewModel: viewModel.commute,
                    showAlerts: actions.showAlerts,
                    selectStop: actions.selectStop,
                    toggleExpansion: actions.toggleFavouriteExpansion
                )
            case .search:
                SearchView(
                    query: $searchQuery,
                    viewModel: viewModel.search,
                    updateSearch: actions.updateSearch,
                    selectStop: actions.selectStop,
                    close: actions.showHome
                )
            case .stopDetail:
                StopDetailView(
                    viewModel: viewModel.stopDetail,
                    toggleFavourite: actions.toggleFavourite,
                    refresh: actions.refreshDepartures,
                    openDirections: actions.showDirections,
                    trackDeparture: actions.trackDeparture,
                    close: actions.showHome
                )
            case .directions:
                RouteView(
                    viewModel: viewModel.route,
                    calculateRoute: actions.calculateRoute,
                    openInAppleMaps: actions.openRouteInAppleMaps,
                    close: actions.showStopDetail
                )
            case .alerts:
                AlertsView(
                    viewModel: viewModel.alerts,
                    refresh: actions.refreshAlerts,
                    close: actions.showHome
                )
            case .settings:
                SettingsView(
                    viewModel: viewModel.settings,
                    checkGTFSUpdate: actions.checkGTFSUpdate,
                    close: actions.showHome
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 34)
    }
}
