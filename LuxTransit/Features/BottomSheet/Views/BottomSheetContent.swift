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
                    selectStop: actions.selectStop
                )
            case .stopDetail:
                StopDetailView(
                    viewModel: viewModel.stopDetail,
                    openDirections: actions.showDirections,
                    trackDeparture: actions.trackDeparture
                )
            case .directions:
                RouteView(
                    viewModel: viewModel.route,
                    calculateRoute: actions.calculateRoute,
                    openInAppleMaps: actions.openRouteInAppleMaps
                )
            case .alerts:
                AlertsView(
                    viewModel: viewModel.alerts
                )
            case .settings:
                SettingsView(
                    viewModel: viewModel.settings,
                    checkGTFSUpdate: actions.checkGTFSUpdate
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 34)
    }
}
