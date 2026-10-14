import SwiftUI

/// The step-by-step timeline of the selected route option: a summary card for
/// the option, then the vertical leg list.
struct RouteTimelineView: View {
    @Environment(RoutePlannerModel.self) private var model
    @Environment(AlertsModel.self) private var alerts
    @Environment(\.routeService) private var routeService

    var body: some View {
        ScrollView {
            content
                .safeAreaPadding(.horizontal, 16)
        }
        .refreshable { await model.refreshSelectedRouteRealtime(using: routeService) }
        .navigationTitle("Selected route")
        .toolbarTitleDisplayMode(.inline)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedOption = model.selectedRouteOption {
                RouteTimelineSummaryCard(option: selectedOption)

                RouteLegList(
                    legs: selectedOption.plan.legs,
                    legAlerts: alerts.legAlerts(forRoute: selectedOption)
                )

                if let message = model.routeStatusMessage {
                    RouteStatusMessage(text: message)
                }

                let routeAlerts = alerts.alerts(forRoute: selectedOption)
                if !routeAlerts.isEmpty {
                    RouteAlertsSection(alerts: routeAlerts)
                }

                ShareLink(
                    item: selectedOption.shareText(
                        originTitle: model.originTitle,
                        destinationTitle: model.destinationTitle
                    )
                ) {
                    Label("Share route", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)
            } else {
                CompactUnavailableCard(
                    title: "No route selected",
                    message: "Choose a route option to see its step-by-step timeline.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
