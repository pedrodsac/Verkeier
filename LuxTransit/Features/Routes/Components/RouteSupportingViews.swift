import SwiftUI

// MARK: - RouteInfoBanner

/// A slim pill shown above the results list while routes are being refreshed.
struct RouteInfoBanner: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.65), in: Capsule())
    }
}

// MARK: - RouteStatusMessage

/// An inline info note shown below route results when a status message is set.
struct RouteStatusMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - RouteAlertsSection

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

// MARK: - RouteOptionSkeletonRow

/// A placeholder card shown while routes are loading, matching the layout of
/// a real ``RouteOptionCard`` so the transition is smooth.
struct RouteOptionSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("00:00 – 00:00  ·  00 min")
                    .font(.callout.weight(.bold))
                Spacer()
                Text("Scheduled")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 5) {
                Text("Bus 000")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)

                Text("Tram T0")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text("0 transfers  ·  0.0 km  ·  Scheduled GTFS times")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            .background.opacity(0.76),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.16), lineWidth: 0.5)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        RouteInfoBanner(title: "Refreshing routes", systemImage: "arrow.trianglehead.clockwise")
        RouteStatusMessage(text: "Fastest option from your current location.")
        RouteOptionSkeletonRow()
        RouteOptionSkeletonRow()
    }
    .padding()
}
#endif
