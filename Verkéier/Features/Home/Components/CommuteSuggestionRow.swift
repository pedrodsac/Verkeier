import SwiftUI

/// Offers directions for the saved commute that fits this time of day.
struct CommuteSuggestionRow: View {
    let preset: RouteCommutePreset

    var body: some View {
        NavigationLink(value: SheetRoute.directionsForPreset(preset.id)) {
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
                .tint.opacity(0.1),
                in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Commute suggestion, \(preset.title), leave now")
    }
}
