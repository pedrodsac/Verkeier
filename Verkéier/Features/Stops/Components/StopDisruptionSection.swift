import SwiftUI

/// The disruptions affecting a stop, above its departures.
struct StopDisruptionSection: View {
    let alerts: [AlertMessage]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Disruption Impact")
                    .font(.headline.weight(.semibold))
                Text("These AVL alerts affect this stop or its served lines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(alerts.prefix(3)) { alert in
                    CompactAlertRow(alert: alert)
                }
            }
        }
    }
}

private struct CompactAlertRow: View {
    let alert: AlertMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(alert.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
