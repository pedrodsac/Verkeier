import SwiftUI

/// Current service alerts from the AVL feed.
struct AlertsScreen: View {
    @Environment(AlertsModel.self) private var model
    @Environment(\.avlClient) private var avlClient
    @Environment(\.disruptionAlertService) private var disruptionAlertService

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
        }
        .navigationTitle("Service Alerts")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refresh) {
                    Label("Refresh alerts", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingAlerts)
            }
        }
    }
}

// MARK: - Subviews

private extension AlertsScreen {
    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.isLoadingAlerts, model.alerts.isEmpty {
                DepartureLoadingCard(title: "Loading alerts")
            } else if let errorMessage = model.alertsErrorMessage {
                CompactUnavailableCard(
                    title: "Alerts unavailable",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                )
            } else if model.alerts.isEmpty {
                CompactUnavailableCard(
                    title: "No current alerts",
                    message: "No AVL messages are available.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.alerts) { alert in
                            AlertCard(alert: alert)
                        }
                    }
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    func refresh() {
        Task {
            await model.refresh(using: avlClient, disruptionAlertService: disruptionAlertService)
        }
    }
}

#Preview {
    let models = FeatureModels()
    models.alerts.alerts = [
        AlertMessage(
            id: "alert-1",
            title: "Line 16 diverted",
            body:
                "Due to roadworks on Avenue de la Gare, buses are diverting via Rue du Fort Rheinsheim until further notice.",
            severity: .warning,
            affectedStopIds: ["stop-1", "stop-2"],
            affectedRouteIds: ["16"],
            startsAt: .now,
            endsAt: nil,
            dataSource: .mock
        ),
        AlertMessage(
            id: "alert-2",
            title: "T1 service restored",
            body: "Tram service between Rout Bréck–Pafendall and Luxexpo has resumed normal operation.",
            severity: .info,
            affectedStopIds: ["stop-3"],
            affectedRouteIds: ["T1"],
            startsAt: .now,
            endsAt: nil,
            dataSource: .mock
        ),
    ]
    return NavigationStack {
        AlertsScreen()
    }
    .previewEnvironment(models)
}
