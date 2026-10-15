import SwiftUI

/// A line's name in white on its mode colour. A funicular shows its symbol
/// instead of a name.
struct LineBadge: View {
    enum Size {
        /// Route option ribbons. Leaves room around the badge for a live status ring.
        case regular
        /// The route timeline, beside the ride's destination.
        case compact

        fileprivate var horizontalInset: CGFloat { self == .regular ? 9 : 6 }
        fileprivate var verticalInset: CGFloat { self == .regular ? 4 : 2 }
        fileprivate var cornerRadius: CGFloat { self == .regular ? 8 : 7 }
        fileprivate var ringMargin: CGFloat { self == .regular ? 3 : 0 }
    }

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let name: String
    let mode: TransportMode
    var size: Size = .regular
    /// Rings the badge in the colour of the line's live status.
    var status: RouteLineStatus? = nil

    var body: some View {
        HStack(spacing: 4) {
            if mode == .funicular {
                Image(systemName: "cablecar")
                    .accessibilityLabel(mode.displayName)
            } else {
                Text(name)
            }
            if differentiateWithoutColor, let status {
                Image(systemName: status.symbol)
            }
        }
        .font(.callout.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, size.horizontalInset)
        .padding(.vertical, size.verticalInset)
        .background(
            mode.tint.gradient,
            in: RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        )
        .padding(size.ringMargin)
        .overlay {
            if let status {
                RoundedRectangle(cornerRadius: size.cornerRadius + size.ringMargin, style: .continuous)
                    .strokeBorder(status.color, lineWidth: 3)
            }
        }
    }
}

#if DEBUG
#Preview("Line status rings", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            LineBadge(name: "16", mode: .bus, status: .onTime)
            LineBadge(name: "850", mode: .bus, status: .delayed)
            LineBadge(name: "T1", mode: .tram, status: .cancelled)
            LineBadge(name: "18", mode: .bus)
        }
        HStack {
            LineBadge(name: "16", mode: .bus, size: .compact)
            LineBadge(name: "T1", mode: .tram, size: .compact)
            LineBadge(name: "Funicular", mode: .funicular, size: .compact)
        }
    }
    .padding()
}
#endif
