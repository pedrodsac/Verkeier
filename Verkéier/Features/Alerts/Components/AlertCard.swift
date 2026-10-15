import SwiftUI

/// One service alert: its severity, title, details and affected lines.
struct AlertCard: View {
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
                AffectedLineBadges(lines: alert.affectedRouteIds)
            }
        }
        .padding(14)
        .background(
            .background.opacity(0.78),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
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

private struct AffectedLineBadges: View {
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
