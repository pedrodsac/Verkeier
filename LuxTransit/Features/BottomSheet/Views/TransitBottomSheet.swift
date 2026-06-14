import SwiftUI

struct TransitBottomSheet: View {
    @Binding var searchQuery: String
    let detent: BottomSheetDetent
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack {
                BottomSheetContent(
                    viewModel: viewModel,
                    searchQuery: $searchQuery,
                    detent: detent,
                    actions: actions
                )
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                .toolbarVisibility(shouldHideNavigationBar ? .hidden : .visible, for: .navigationBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(viewModel.context.accessibilityLabel)
            }

            if viewModel.context == .stopDetail {
                StopDetailFloatingActions(
                    isFavourite: viewModel.stopDetail.isFavourite,
                    isRefreshDisabled: viewModel.stopDetail.isLoadingDepartures,
                    toggleFavourite: actions.toggleFavourite,
                    refreshDepartures: actions.refreshDepartures
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .zIndex(1)
            }
        }
    }

    private var shouldHideNavigationBar: Bool {
        detent == .collapsed || viewModel.context == .search
            || (detent == .medium && viewModel.context == .home)
    }

    private var navigationTitle: String {
        switch viewModel.context {
        case .home:
            viewModel.commute.hasFavourites ? "Commute" : "Nearby"
        case .search:
            "Search"
        case .stopDetail:
            viewModel.stopDetail.stop?.name ?? "Selected Stop"
        case .directions:
            "Directions"
        case .alerts:
            "Service Alerts"
        case .settings:
            "Settings"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch viewModel.context {
        case .home:
            if viewModel.commute.activeAlertCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: actions.showAlerts) {
                        Label("Show alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                    .tint(.orange)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.showSettings) {
                    Label("Settings", systemImage: "ellipsis.circle")
                }
            }

        case .search:
            ToolbarItem(placement: .topBarTrailing) {
                EmptyView()
            }

        case .stopDetail:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close stop details", systemImage: "chevron.down")
                }
            }

        case .directions:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showStopDetail) {
                    Label("Back to stop", systemImage: "chevron.left")
                }
            }

        case .alerts:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close alerts", systemImage: "chevron.down")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.refreshAlerts) {
                    Label("Refresh alerts", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.alerts.isLoading)
            }

        case .settings:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close settings", systemImage: "chevron.down")
                }
            }
        }
    }
}

private struct StopDetailFloatingActions: View {
    let isFavourite: Bool
    let isRefreshDisabled: Bool
    let toggleFavourite: () -> Void
    let refreshDepartures: () -> Void

    var body: some View {
        HStack {
            Button(action: toggleFavourite) {
                Label(
                    isFavourite ? "Remove favourite" : "Save favourite",
                    systemImage: isFavourite ? "star.fill" : "star"
                )
            }
            .tint(isFavourite ? .yellow : nil)

            Spacer()

            Button(action: refreshDepartures) {
                Label("Refresh departures", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshDisabled)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }
}
