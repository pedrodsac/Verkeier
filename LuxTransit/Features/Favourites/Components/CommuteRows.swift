import SwiftUI

struct CommuteSuggestionRow: View {
    let preset: RouteCommutePreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Leave now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(
                .tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Commute suggestion, \(preset.title), leave now")
    }
}

struct AlertsSummaryRow: View {
    let alertCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(alertText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                .orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(alertText)
    }

    private var alertText: String {
        alertCount == 1 ? "1 active disruption" : "\(alertCount) active disruptions"
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    AlertsSummaryRow(alertCount: 3, action: {})
        .padding(.horizontal, 16)
}
