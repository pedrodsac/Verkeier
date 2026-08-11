import SwiftUI

/// The route step-by-step timeline navigation destination.
///
/// Shows a summary card for the selected option (ribbon + times) followed by
/// the vertical-rail leg list. Falls back to an unavailable card if no option
/// is selected.
struct RouteTimelineView: View {
    let viewModel: RoutePresentationModel
    let openInAppleMaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedOption = viewModel.selectedRouteOption {
                // Summary card matching the chosen option card
                RouteTimelineSummaryCard(option: selectedOption)

                // Vertical leg-by-leg timeline
                RouteLegList(legs: selectedOption.plan.legs, legAlerts: viewModel.legAlerts)

                // Journey alerts
                if !viewModel.alerts.isEmpty {
                    RouteAlertsSection(alerts: viewModel.alerts)
                }
            } else {
                CompactUnavailableCard(
                    title: "No route selected",
                    message: "Choose a route option to see its step-by-step timeline.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }

            // Apple Maps handoff
            Button(action: openInAppleMaps) {
                Label("Open in Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.primary)
            .disabled(viewModel.selectedStop == nil && viewModel.destination == nil)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
