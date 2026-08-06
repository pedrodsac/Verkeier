import SwiftUI

struct AlertsView: View {
    let viewModel: AlertsPresentationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AlertRefreshStatus(lastUpdated: viewModel.lastUpdated, isStale: viewModel.isStale)

            if viewModel.isLoading, viewModel.alerts.isEmpty {
                DepartureLoadingCard(title: "Loading alerts")
            } else if let errorMessage = viewModel.errorMessage {
                CompactUnavailableCard(
                    title: "Alerts unavailable",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                )
            } else if viewModel.alerts.isEmpty {
                CompactUnavailableCard(
                    title: "No current alerts",
                    message: "No AVL messages are available.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.alerts) { alert in
                            AlertCard(alert: alert)
                        }
                    }
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

#Preview {
    AlertsView(
        viewModel: AlertsPresentationModel(
            alerts: [
                AlertMessage(
                    id: "alert-1",
                    title: "Line 16 diverted",
                    body: "Due to roadworks on Avenue de la Gare, buses are diverting via Rue du Fort Rheinsheim until further notice.",
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
                )
            ],
            isLoading: false,
            errorMessage: nil,
            lastUpdated: .now,
            isStale: false
        )
    )
    .padding(.horizontal, 16)
}

private struct AlertRefreshStatus: View {
    let lastUpdated: Date?
    let isStale: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isStale ? .orange : .green)
                .contentTransition(.symbolEffect(.replace))
                .animation(Animation.respectingReduceMotion(.snappy, reduceMotion), value: isStale)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        guard let lastUpdated else { return "Not updated yet" }
        let formatted = lastUpdated.formatted(date: .omitted, time: .shortened)
        return isStale ? "Stale · updated \(formatted)" : "Updated \(formatted)"
    }
}

private struct AlertCard: View {
    let alert: AlertMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(severityTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(iconColor)
                            .textCase(.uppercase)
                        Spacer(minLength: 0)
                    }

                    Text(alert.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !alert.body.isEmpty {
                Text(alert.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !alert.affectedRouteIds.isEmpty {
                FlowLineChips(lines: alert.affectedRouteIds)
            }
        }
        .padding(14)
        .background(
            .background.opacity(0.78), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(iconColor.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var severityTitle: String {
        switch alert.severity {
        case .info: "Info"
        case .warning: "Disruption"
        case .severe: "Severe"
        case .unknown: "Notice"
        }
    }

    private var iconName: String {
        switch alert.severity {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .severe: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch alert.severity {
        case .info: .blue
        case .warning: .orange
        case .severe: .red
        case .unknown: .secondary
        }
    }
}

private struct FlowLineChips: View {
    let lines: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
            }

            VStack(alignment: .leading, spacing: 6) {
                chips
            }
        }
    }

    private var chips: some View {
        ForEach(lines.prefix(8), id: \.self) { line in
            Text(line)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
    }
}
