import SwiftUI

/// Root content for the Plan tab. The existing route view intentionally keeps
/// planning inputs and results together so alternatives remain in context.
struct PlanView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions

    var body: some View {
        ScrollView {
            RouteView(viewModel: viewModel, actions: actions)
                .safeAreaPadding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle("Plan")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RoutePlanningTimeButton(
                    current: viewModel.planningTime,
                    onChange: actions.setRoutePlanningTime
                )
            }
        }
    }
}
