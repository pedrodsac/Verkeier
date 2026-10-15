import SwiftUI

/// One stop of a vehicle run, with its platform and scheduled and live times.
struct TripStopRow: View {
    let row: TripStopItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                stopName
                Spacer(minLength: 12)
                times
            }
            HStack(alignment: .center) {
                Text(row.platform.map { "Platform \($0)" } ?? "Platform unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if row.status != "Live time unavailable" {
                    Text(row.status).font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .accessibilityLabel(row.accessibilityStatus)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.isInRide ? "Part of your ride" : "")
    }

    private var stopName: some View {
        Text(row.name).font(.body.weight(row.isInRide ? .semibold : .regular))
            .foregroundStyle(row.isPassed ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var times: some View {
        HStack(spacing: 5) {
            if let scheduled = row.scheduledTime {
                Text(scheduled, style: .time)
                    .foregroundStyle(row.isPassed || row.liveTime != nil ? .secondary : .primary)
                    .strikethrough(row.liveTime != nil)
            }
            if let live = row.liveTime {
                Text(live, style: .time)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            }
        }
        .font(.subheadline).monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusColor: Color {
        switch row.statusTint {
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .secondary: .secondary
        }
    }
}
