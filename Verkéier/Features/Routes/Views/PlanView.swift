import SwiftUI

/// Root content for the Plan tab. The existing route view intentionally keeps
/// planning inputs and results together so alternatives remain in context.
struct PlanView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions

    var body: some View {
        RouteView(viewModel: viewModel, actions: actions)
        .refreshable { await actions.refreshRoutes() }
        .navigationTitle("Plan")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                RouteOptionsBar(
                    filters: viewModel.filters,
                    hasDestination: viewModel.hasDestination,
                    updateRouteFilters: actions.updateRouteFilters,
                    saveCurrentCommutePreset: actions.saveCurrentCommutePreset
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                RoutePlanningTimeButton(
                    current: viewModel.planningTime,
                    onChange: actions.setRoutePlanningTime
                )
            }
        }
    }
}
