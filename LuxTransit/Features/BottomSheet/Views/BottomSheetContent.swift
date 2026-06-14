import SwiftUI

struct BottomSheetContent: View {
    let viewModel: TransitSheetPresentationModel
    @Binding var searchQuery: String
    let detent: BottomSheetDetent
    let actions: TransitSheetActions

    var body: some View {
        Group {
            if detent == .collapsed {
                CollapsedSearchContent(query: searchQuery, action: actions.showSearch)
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, detent == .collapsed ? 0 : 34)
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

                Text(query.isEmpty ? "Search Maps" : query)
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
        case collapsed

        var height: CGFloat {
            switch self {
            case .regular: 44
            case .collapsed: 52
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: 12
            case .collapsed: 18
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular: 12
            case .collapsed: 26
            }
        }

        var iconFont: Font {
            switch self {
            case .regular: .body.weight(.semibold)
            case .collapsed: .title3.weight(.semibold)
            }
        }

        var textFont: Font {
            switch self {
            case .regular: .body
            case .collapsed: .title3
            }
        }

        var background: AnyShapeStyle {
            switch self {
            case .regular: AnyShapeStyle(.quaternary.opacity(0.7))
            case .collapsed: AnyShapeStyle(.background.opacity(0.86))
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .regular: 0
            case .collapsed: 0.22
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .regular: 0
            case .collapsed: 0.08
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .regular: 0
            case .collapsed: 10
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .regular: 0
            case .collapsed: 2
            }
        }
    }
}
