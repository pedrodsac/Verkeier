import SwiftUI

struct TransitBottomSheet: View {
    private enum SheetTab: Hashable {
        case home
        case placeholderOne
        case placeholderTwo
        case settings
    }

    private let searchBarContentTopPadding: CGFloat = 80

    @Binding var searchQuery: String
    @Binding var path: [TransitSheetRoute]
    let detent: BottomSheetDetent
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions
    let activateRoute: (TransitSheetRoute?, TransitSheetRoute?, Bool) -> Void

    @State private var isSearchActive = false
    @State private var focusSearch = false
    @State private var selectedTab: SheetTab = .home

    var body: some View {
        tabView
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(tabBarBackground, for: .tabBar)
            .padding(.horizontal, isCollapsed ? 28 : 0)
            .padding(.vertical, isCollapsed ? 16 : 0)
            .background {
                if isCollapsed {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
        .onChange(of: path) { oldPath, newPath in
            isSearchActive = newPath.last == .search
            focusSearch = newPath.last == .search

            guard oldPath != newPath else { return }
            let isBackNavigation = newPath.count < oldPath.count
                && Array(oldPath.prefix(newPath.count)) == newPath
            activateRoute(newPath.last, oldPath.last, isBackNavigation)
        }
        .onChange(of: detent) { _, newDetent in
            if newDetent == .collapsed {
                isSearchActive = false
                focusSearch = false
            }
        }
        .onAppear {
            isSearchActive = isSearchRoute
            focusSearch = isSearchRoute
        }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: SheetTab.home) {
                homeTab
            }

            Tab("Placeholder 1", systemImage: "square.dashed", value: SheetTab.placeholderOne) {
                PlaceholderTab(title: "Placeholder 1", systemImage: "square.dashed")
            }

            Tab("Placeholder 2", systemImage: "ellipsis", value: SheetTab.placeholderTwo) {
                PlaceholderTab(title: "Placeholder 2", systemImage: "ellipsis")
            }

            Tab("Settings", systemImage: "gear", value: SheetTab.settings) {
                NavigationStack {
                    SettingsView(
                        viewModel: viewModel.settings,
                        checkGTFSUpdate: actions.checkGTFSUpdate,
                        setDebugDataMode: actions.setDebugDataMode
                    )
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }

    private var isCollapsed: Bool {
        detent == .collapsed
    }

    private var tabBarBackground: AnyShapeStyle {
        if isCollapsed {
            return AnyShapeStyle(Color(.systemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var homeTab: some View {
        NavigationStack(path: $path) {
            BottomSheetContent(
                query: $searchQuery,
                isSearchActive: $isSearchActive,
                detent: detent,
                contentTopPadding: shouldShowSearchBar ? searchBarContentTopPadding : 0,
                viewModel: viewModel.commute,
                searchViewModel: viewModel.search,
                searchActions: SearchActions(from: actions)
            )
            .navigationDestination(for: TransitSheetRoute.self) { route in
                destination(for: route)
            }
        }
        .toolbarVisibility(navigationBarVisibility, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if shouldShowSearchBar {
                StopSearchBar(
                    text: $searchQuery,
                    isActive: $isSearchActive,
                    focusRequested: $focusSearch,
                    onActivate: activateSearch,
                    onCancel: cancelSearch
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
        }
    }

    private var isSearchRoute: Bool {
        path.last == .search
    }

    private var shouldShowSearchBar: Bool {
        !isCollapsed && (path.isEmpty || isSearchRoute)
    }

    private var navigationBarVisibility: Visibility {
        if detent == .collapsed || shouldShowSearchBar {
            .hidden
        } else {
            .visible
        }
    }

    private func cancelSearch() {
        searchQuery = ""
        isSearchActive = false
        focusSearch = false
        actions.showHome()
    }

    private func activateSearch() {
        guard detent != .expanded else { return }
        actions.expandSheet()
    }

    @ViewBuilder
    private func destination(for route: TransitSheetRoute) -> some View {
        switch route {
        case .search:
            SearchView(
                query: $searchQuery,
                viewModel: viewModel.search,
                actions: SearchActions(from: actions)
            )
            .safeAreaPadding(.horizontal, 16)
            .padding(.top, searchBarContentTopPadding)

        case .stopGroup:
            ScrollView {
                StopGroupView(viewModel: viewModel.stopGroup)
                    .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)

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
            .navigationBarTitleDisplayMode(.inline)
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
                .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RoutePlanningTimeButton(
                        current: viewModel.route.planningTime,
                        onChange: actions.setRoutePlanningTime
                    )
                }
            }

        case .routeTimeline:
            ScrollView {
                RouteTimelineView(
                    viewModel: viewModel.route,
                    openInAppleMaps: actions.openRouteInAppleMaps
                )
                .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        case .lineDetail:
            LineDetailView(
                viewModel: viewModel.lineDetail,
                actions: LineDetailActions(from: actions)
            )
            .navigationTitle(route.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)

        case .alerts:
            ScrollView {
                AlertsView(viewModel: viewModel.alerts)
                    .padding(.horizontal, 16)
            }
            .navigationTitle(route.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
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

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("This tab is reserved for a future feature.")
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Route planning time

/// Toolbar calendar menu for choosing when to travel. A menu offers
/// "Leave now / Leave at… / Arrive by…"; the latter two open a sheet to pick the
/// time.
private struct RoutePlanningTimeButton: View {
    let current: RoutePlanningTime
    let onChange: (RoutePlanningTime) -> Void

    @State private var editing: Mode?
    @State private var date: Date = .now

    private enum Mode: Identifiable {
        case leave, arrive
        var id: Int {
            self == .leave ? 0 : 1
        }

        var title: String {
            self == .leave ? "Leave at" : "Arrive by"
        }

        func planningTime(_ date: Date) -> RoutePlanningTime {
            self == .leave ? .departAt(date) : .arriveBy(date)
        }
    }

    var body: some View {
        Menu {
            Button {
                onChange(.leaveNow)
            } label: {
                Label("Leave now", systemImage: current.isNow ? "checkmark" : "clock")
            }
            Button {
                date = current.date ?? .now
                editing = .leave
            } label: {
                Label("Leave at…", systemImage: "calendar")
            }
            Button {
                date = current.date ?? .now
                editing = .arrive
            } label: {
                Label("Arrive by…", systemImage: "flag.checkered")
            }
        } label: {
            Label(
                "Choose travel time",
                systemImage: current.isNow ? "calendar" : "calendar.badge.clock"
            )
        }
        .tint(current.isNow ? nil : .blue)
        .sheet(item: $editing) { mode in
            NavigationStack {
                DatePicker(
                    "Time",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle(mode.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onChange(mode.planningTime(date))
                            editing = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
