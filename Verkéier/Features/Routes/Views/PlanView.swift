import SwiftUI

/// The route planner screen. It is the Plan tab's root, and is also pushed to
/// show directions for a saved commute.
struct PlanView: View {
    enum Context {
        /// The Plan tab's root, with route options in the toolbar.
        case tab
        /// Pushed from Home to plan a saved commute.
        case commute
    }

    @Environment(RoutePlannerModel.self) private var model
    @Environment(SheetRouter.self) private var router

    var context: Context = .tab

    var body: some View {
        ScrollView {
            RouteView()
                .safeAreaPadding(.horizontal, 16)
                .padding(.bottom, context == .tab ? 12 : 0)
        }
        .refreshable { await router.refreshRoutes() }
        .navigationTitle(context == .tab ? "Plan" : "Directions")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if context == .tab {
                ToolbarItem(placement: .topBarLeading) {
                    RouteOptionsBar(
                        filters: model.routeFilters,
                        hasDestination: model.hasDestination,
                        updateRouteFilters: router.updateRouteFilters,
                        saveCurrentCommutePreset: { model.saveCurrentCommutePreset(title: $0) }
                    )
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                RoutePlanningTimeButton(
                    current: model.routePlanningTime,
                    onChange: router.setRoutePlanningTime
                )
            }
        }
    }
}
