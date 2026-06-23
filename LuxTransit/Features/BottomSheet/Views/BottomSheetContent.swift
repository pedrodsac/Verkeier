import SwiftUI

struct BottomSheetContent: View {
    let viewModel: TransitSheetPresentationModel
    @Binding var searchQuery: String
    let detent: BottomSheetDetent
    let actions: TransitSheetActions

    var body: some View {
        if detent == .collapsed {
            CollapsedSearchContent(query: searchQuery, action: actions.showSearch)
                .safeAreaPadding(.horizontal, 16)
        } else if viewModel.context == .settings {
            SettingsView(
                viewModel: viewModel.settings,
                checkGTFSUpdate: actions.checkGTFSUpdate,
                setDebugDataMode: actions.setDebugDataMode
            )
        } else {
            ScrollView {
                switch viewModel.context {
                case .home:
                    HomeSheetContent(
                        query: searchQuery,
                        detent: detent,
                        viewModel: viewModel.commute,
                        showSearch: actions.showSearch,
                        showSettings: actions.showSettings,
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
                        cancel: actions.showHome
                    )
                case .stopDetail:
                    StopDetailView(
                        viewModel: viewModel.stopDetail,
                        openDirections: actions.showDirections,
                        startTrackingDeparture: actions.startTrackingDeparture,
                        stopTrackingDeparture: actions.stopTrackingDeparture,
                        scheduleDepartureReminder: actions.scheduleDepartureReminder,
                        cancelDepartureReminder: actions.cancelDepartureReminder,
                        toggleDepartureLine: actions.toggleDepartureLine,
                        showLineDetail: actions.showLineDetail,
                        selectDeparturePlatform: actions.selectDeparturePlatform
                    )
                case .directions:
                    RouteView(
                        viewModel: viewModel.route,
                        calculateRoute: actions.calculateRoute,
                        selectRouteOption: actions.selectRouteOption,
                        showMoreRouteOptions: actions.showMoreRouteOptions,
                        openInAppleMaps: actions.openRouteInAppleMaps,
                        selectRouteOrigin: actions.selectRouteOrigin,
                        selectRouteDestination: actions.selectRouteDestination,
                        applyCommutePreset: actions.applyCommutePreset,
                        saveCurrentCommutePreset: actions.saveCurrentCommutePreset,
                        swapRouteEndpoints: actions.swapRouteEndpoints,
                        updateRouteFilters: actions.updateRouteFilters
                    )
                case .routeTimeline:
                    RouteTimelineView(
                        viewModel: viewModel.route,
                        openInAppleMaps: actions.openRouteInAppleMaps
                    )
                case .lineDetail:
                    LineDetailView(
                        viewModel: viewModel.lineDetail,
                        selectStop: actions.selectStop,
                        selectDirection: actions.selectLineDetailDirection
                    )
                case .alerts:
                    AlertsView(
                        viewModel: viewModel.alerts
                    )
                case .settings:
                    EmptyView()
                }
            }
            .safeAreaPadding(.horizontal, 16)
            .refreshableWhen(viewModel.context == .stopDetail, action: actions.refreshDepartures)
        }
    }
}

private extension View {
    @ViewBuilder
    func refreshableWhen(_ enabled: Bool, action: @escaping () async -> Void) -> some View {
        if enabled {
            refreshable { await action() }
        } else {
            self
        }
    }
}

private struct HomeSheetContent: View {
    let query: String
    let detent: BottomSheetDetent
    let viewModel: CommuteDashboardViewModel
    let showSearch: () -> Void
    let showSettings: () -> Void
    let showAlerts: () -> Void
    let selectStop: (Stop) -> Void
    let toggleExpansion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: detent == .medium ? 22 : 16) {
            if detent == .medium {
                mediumHeader
            } else {
                BottomSheetSearchButton(query: query, action: showSearch)
            }

            CommuteDashboardView(
                viewModel: viewModel,
                displayStyle: detent == .medium ? .mapsMedium : .regular,
                showAlerts: showAlerts,
                selectStop: selectStop,
                toggleExpansion: toggleExpansion
            )
        }
    }

    private var mediumHeader: some View {
        HStack(spacing: 12) {
            BottomSheetSearchButton(query: query, style: .medium, action: showSearch)

            Button(action: showSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.background.opacity(0.86), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.separator.opacity(0.22), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 2)
                    .contentShape(Circle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings and information")
        }
        .padding(.top, 14)
    }
}

private struct CollapsedSearchContent: View {
    let query: String
    let action: () -> Void

    var body: some View {
        VStack {
            BottomSheetSearchButton(query: query, style: .collapsed, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct BottomSheetSearchButton: View {
    let query: String
    var style: SearchButtonStyle = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(style.iconFont)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(query.isEmpty ? "Search stops" : query)
                    .font(style.textFont)
                    .foregroundStyle(query.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: style.height)
            .padding(.horizontal, style.horizontalPadding)
            .background(style.background, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(.separator.opacity(style.strokeOpacity), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(style.shadowOpacity), radius: style.shadowRadius, y: style.shadowY)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search stops")
    }

    enum SearchButtonStyle {
        case regular
        case medium
        case collapsed

        var height: CGFloat {
            switch self {
            case .regular: 44
            case .medium: 52
            case .collapsed: 52
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: 12
            case .medium: 18
            case .collapsed: 18
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular: 12
            case .medium: 26
            case .collapsed: 26
            }
        }

        var iconFont: Font {
            switch self {
            case .regular: .body.weight(.semibold)
            case .medium: .title3.weight(.semibold)
            case .collapsed: .title3.weight(.semibold)
            }
        }

        var textFont: Font {
            switch self {
            case .regular: .body
            case .medium: .title3
            case .collapsed: .title3
            }
        }

        var background: AnyShapeStyle {
            switch self {
            case .regular: AnyShapeStyle(.quaternary.opacity(0.7))
            case .medium: AnyShapeStyle(.background.opacity(0.86))
            case .collapsed: AnyShapeStyle(.background.opacity(0.86))
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .regular: 0
            case .medium: 0.22
            case .collapsed: 0.22
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .regular: 0
            case .medium: 0.08
            case .collapsed: 0.08
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .regular: 0
            case .medium: 10
            case .collapsed: 10
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .regular: 0
            case .medium: 2
            case .collapsed: 2
            }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    BottomSheetSearchButton(query: "Search stops", action: {})
        .padding(.horizontal, 16)
}

#Preview(traits: .sizeThatFitsLayout) {
    BottomSheetSearchButton(query: "", style: .medium, action: {})
        .padding(.horizontal, 16)
}

#Preview(traits: .sizeThatFitsLayout) {
    BottomSheetSearchButton(query: "", style: .collapsed, action: {})
        .padding(.horizontal, 16)
}
