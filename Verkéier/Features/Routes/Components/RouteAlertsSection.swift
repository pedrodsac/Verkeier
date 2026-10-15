import SwiftUI

/// Compact journey-alert cards shown when a planned route has active disruptions.
struct RouteAlertsSection: View {
    let alerts: [AlertMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Journey Alerts")
                .font(.headline.weight(.semibold))
            ForEach(alerts.prefix(3)) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                    Text(alert.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .orange.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.orange.opacity(0.25), lineWidth: 0.5)
                }
            }
        }
    }
}
