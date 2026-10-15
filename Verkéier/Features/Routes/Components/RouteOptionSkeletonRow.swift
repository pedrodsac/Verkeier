import SwiftUI

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

            Text("0 transfers  ·  0.0 km  ·  Scheduled times")
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
        RouteStatusMessage(text: "Fastest option from your current location.")
        RouteOptionSkeletonRow()
        RouteOptionSkeletonRow()
    }
    .padding()
}
#endif
