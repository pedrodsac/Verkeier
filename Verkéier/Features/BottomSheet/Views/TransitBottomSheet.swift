import SwiftUI

struct TransitBottomSheet: View {
    private let searchBarContentTopPadding: CGFloat = 80

    @Environment(AppPreferences.self) private var preferences
    @Environment(SheetRouter.self) private var router
    @Environment(SearchModel.self) private var search

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
            .onChange(of: router.homePath) { oldPath, newPath in
                isSearchActive = newPath.last == .search
                focusSearch = newPath.last == .search
                router.pathDidChange(from: oldPath, to: newPath)
            }
            .onChange(of: router.planPath) { oldPath, newPath in
                router.pathDidChange(from: oldPath, to: newPath)
            }
            .onAppear {
                isSearchActive = isSearchRoute
                focusSearch = isSearchRoute
            }
    }

    private var tabView: some View {
        TabView(selection: Bindable(router).selectedTab) {
            Tab("Home", systemImage: "train.side.front.car", value: TransitSheetTab.home) {
                homeTab
            }

            Tab("Plan", systemImage: "arrow.triangle.turn.up.right.diamond", value: TransitSheetTab.plan) {
                planTab
            }

            Tab("Settings", systemImage: "gear", value: TransitSheetTab.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .toolbarTitleDisplayMode(.inline)
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }

    private var homeTab: some View {
        NavigationStack(path: Bindable(router).homePath) {
            BottomSheetContent(
                isSearchActive: isSearchActive,
                contentTopPadding: shouldShowSearchBar ? searchBarContentTopPadding : 0
            )
            .navigationDestination(for: TransitSheetRoute.self) { route in
                TransitSheetDestinationView(route: route, searchContentTopPadding: searchBarContentTopPadding)
            }
        }
        .toolbarVisibility(navigationBarVisibility, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if shouldShowSearchBar {
                StopSearchBar(
                    text: Bindable(search).searchQuery,
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

    private var planTab: some View {
        NavigationStack(path: Bindable(router).planPath) {
            PlanView()
                .navigationDestination(for: TransitSheetRoute.self) { route in
                    TransitSheetDestinationView(route: route)
                }
        }
    }

    private var tabBarBackground: AnyShapeStyle {
        return AnyShapeStyle(.regularMaterial)
    }

    private var isSearchRoute: Bool {
        router.homePath.last == .search
    }

    private var shouldShowSearchBar: Bool {
        router.selectedTab == .home && (router.homePath.isEmpty || isSearchRoute)
    }

    private var navigationBarVisibility: Visibility {
        if shouldShowSearchBar {
            .hidden
        } else {
            .visible
        }
    }

    private func cancelSearch() {
        search.searchQuery = ""
        isSearchActive = false
        focusSearch = false
        router.showHome()
    }

    private func activateSearch() {
        guard router.detent != .expanded else { return }
        router.expand()
    }
}
