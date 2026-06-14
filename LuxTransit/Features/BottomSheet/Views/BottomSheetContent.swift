import SwiftUI

struct BottomSheetContent: View {
    let viewModel: TransitSheetPresentationModel
    @Binding var searchQuery: String
    let actions: TransitSheetActions

    var body: some View {
        Group {
            switch viewModel.context {
            case .home:
                VStack(alignment: .leading, spacing: 16) {
                    BottomSheetSearchButton(query: searchQuery, action: actions.showSearch)

                    CommuteDashboardView(
                        viewModel: viewModel.commute,
                        showAlerts: actions.showAlerts,
                        selectStop: actions.selectStop,
                        toggleExpansion: actions.toggleFavouriteExpansion
                    )
                }
            case .search:
                SearchView(
                    query: $searchQuery,
                    viewModel: viewModel.search,
                    updateSearch: actions.updateSearch,
                    selectStop: actions.selectStop,
                    cancel: actions.showHome
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

private struct BottomSheetSearchButton: View {
    let query: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(query.isEmpty ? "Search Maps" : query)
                    .font(.body)
                    .foregroundStyle(query.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search stops")
    }
}
