import SwiftUI

/// Row content only; the enclosing List supplies the system reorder control.
struct RouteEndpointRow: View {
    let endpoint: RouteEndpoint
    let title: String
    let place: RoutePlace?
    let canSwap: Bool
    let select: () -> Void
    let swap: () -> Void

    @ScaledMetric(relativeTo: .body) private var badgeSize = 32

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: isCurrentLocation ? "location.fill" : mode.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .background((isCurrentLocation || mode == .unknown ? Color.blue : mode.tint).gradient, in: .circle)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(endpoint == .origin ? Text("From: \(title)") : Text("To: \(title)"))
        .accessibilityHint("Choose a different place")
        .accessibilityActions {
            if canSwap {
                Button("Swap origin and destination", action: swap)
            }
        }
    }

    private var isCurrentLocation: Bool {
        place?.source == .currentLocation || (endpoint == .origin && place == nil)
    }

    private var mode: TransportMode { place?.modes.primaryMode ?? .unknown }
}
