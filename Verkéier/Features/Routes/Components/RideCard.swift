import SwiftUI

/// One compact card holding a ride's line badge and its destination, as the
/// route timeline shows it.
struct RideCard: View {
    let routeText: String
    let mode: TransportMode
    let direction: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            card {
                destinationText
                    .fixedSize(horizontal: true, vertical: false)
            }

            card {
                if let direction, !direction.isEmpty {
                    OverflowMarqueeText(
                        text: direction,
                        font: .subheadline.weight(.semibold),
                        initialLeadingInset: 0,
                        forceScroll: true,
                        foregroundColor: .black
                    )
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationText: some View {
        Text(direction ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }

    private func card<Destination: View>(
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            LineBadge(name: routeText, mode: mode, size: .compact)
            destination()
        }
        .foregroundStyle(.black)
        .padding(3)
        .padding(.trailing, 5)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 0.75, x: 0, y: 0)
    }
}
