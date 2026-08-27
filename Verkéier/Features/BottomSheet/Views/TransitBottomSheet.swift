import SwiftUI

struct TransitBottomSheet: View {
    private let searchBarContentTopPadding: CGFloat = 80

    @Binding var searchQuery: String
    @Environment(AppPreferences.self) private var preferences
    let detent: BottomSheetDetent
    @Bindable var navigation: TransitSheetNavigationState
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions
    let activateRoute: (TransitSheetRoute?, TransitSheetRoute?, Bool) -> Void
    let selectedTab: (TransitSheetTab) -> Void

    @State private var isSearchActive = false
    @State private var focusSearch = false

    var body: some View {
        tabView
            // A sheet has its own presentation host. Keep its preferred scheme
            // connected to the shared preference so changing the theme while
            // the sheet is open updates the sheet as well as the map window.
            .preferredColorScheme(preferences.appearance.colorScheme)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(tabBarBackground, for: .tabBar)
            .onChange(of: navigation.homePath) { oldPath, newPath in
                isSearchActive = newPath.last == .search
                focusSearch = newPath.last == .search
                activatePath(newPath, previous: oldPath)
            }
            .onChange(of: navigation.favouritesPath) { oldPath, newPath in
                activatePath(newPath, previous: oldPath)
            }
            .onChange(of: navigation.planPath) { oldPath, newPath in
                activatePath(newPath, previous: oldPath)
            }
            .onChange(of: navigation.selectedTab) { _, tab in
                guard detent == .collapsed else { return }
                selectedTab(tab)
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
        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "train.side.front.car", value: TransitSheetTab.home) {
                homeTab
            }

            Tab("Favourites", systemImage: "star", value: TransitSheetTab.favourites) {
                favouritesTab
            }

            Tab("Plan", systemImage: "arrow.triangle.turn.up.right.diamond", value: TransitSheetTab.plan) {
                planTab
            }

            Tab("Settings", systemImage: "gear", value: TransitSheetTab.settings) {
                NavigationStack {
                    SettingsView(
                        viewModel: viewModel.settings,
                        checkGTFSUpdate: actions.checkGTFSUpdate,
                        setDebugDataMode: actions.setDebugDataMode
                    )
                    .navigationTitle("Settings")
					.toolbarTitleDisplayMode(.inline)
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }

    private var homeTab: some View {
        NavigationStack(path: $navigation.homePath) {
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
                TransitSheetDestinationView(
                    route: route,
                    searchQuery: $searchQuery,
                    searchContentTopPadding: searchBarContentTopPadding,
                    viewModel: viewModel,
                    actions: actions
                )
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

    private var favouritesTab: some View {
        NavigationStack(path: $navigation.favouritesPath) {
            FavouritesView(viewModel: viewModel.favourites, actions: actions.favourites)
            	.padding(.horizontal, 16)
            	.navigationTitle("Favourites")
            	.toolbarTitleDisplayMode(.inline)
            	.navigationDestination(for: TransitSheetRoute.self) { route in
            	    TransitSheetDestinationView(
            	        route: route,
            	        searchQuery: $searchQuery,
            	        viewModel: viewModel,
            	        actions: actions
            	    )
            	}
        }
    }

    private var planTab: some View {
        NavigationStack(path: $navigation.planPath) {
            PlanView(viewModel: viewModel.route, actions: RouteActions(from: actions))
                .navigationDestination(for: TransitSheetRoute.self) { route in
                    TransitSheetDestinationView(
                        route: route,
                        searchQuery: $searchQuery,
                        viewModel: viewModel,
                        actions: actions
                    )
                }
        }
    }

    private var isCollapsed: Bool {
        detent == .collapsed
    }

    private var tabBarBackground: AnyShapeStyle {
        if isCollapsed {
            return AnyShapeStyle(Color(.clear))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var isSearchRoute: Bool {
        navigation.homePath.last == .search
    }

    private var shouldShowSearchBar: Bool {
        navigation.selectedTab == .home && !isCollapsed && (navigation.homePath.isEmpty || isSearchRoute)
    }

    private var navigationBarVisibility: Visibility {
        if detent == .collapsed || shouldShowSearchBar {
            .hidden
        } else {
            .visible
        }
    }

    private func activatePath(_ path: [TransitSheetRoute], previous: [TransitSheetRoute]) {
        guard path != previous else { return }
        let isBackNavigation = path.count < previous.count
            && Array(previous.prefix(path.count)) == path
        activateRoute(path.last, previous.last, isBackNavigation)
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
}
