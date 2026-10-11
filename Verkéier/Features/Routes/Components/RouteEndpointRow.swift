import SwiftUI

struct RouteEndpointRow: View {
    let endpoint: RouteEndpoint
    let title: String
    let place: RoutePlace?
    let canSwap: Bool
    let dragSessionID: UUID
    let select: () -> Void
    let swap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var badgeSize = 32
    @State private var isDropTargeted = false
    @State private var swapFeedback = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 10) {
                    badge
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(endpoint == .origin ? Text("From: \(title)") : Text("To: \(title)"))
            .accessibilityHint("Choose a different place")
            .accessibilityActions {
                if canSwap {
                    Button("Swap origin and destination", action: performSwap)
                }
            }

            if canSwap {
                handle
                    .draggable(RouteEndpointDragPayload(sessionID: dragSessionID, isOrigin: endpoint == .origin)) {
                        HStack(spacing: 12) {
                            badge
                            Text(title).font(.body).foregroundStyle(.primary)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: .rect(cornerRadius: 18))
                    }
            } else {
                handle
            }
        }
        .background(isDropTargeted && canSwap ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(.rect)
        .dropDestination(for: RouteEndpointDragPayload.self) { items, _ in
            guard canSwap, items.count == 1, let item = items.first,
                  item.sessionID == dragSessionID,
                  item.isOrigin != (endpoint == .origin) else { return false }
            performSwap()
            return true
        } isTargeted: { isDropTargeted = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isDropTargeted)
        .sensoryFeedback(.selection, trigger: swapFeedback)
    }

    private var badge: some View {
        Image(systemName: isCurrentLocation ? "location.fill" : mode.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: badgeSize, height: badgeSize)
            .background((isCurrentLocation || mode == .unknown ? Color.blue : mode.tint).gradient, in: .circle)
            .accessibilityHidden(true)
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(width: 44, height: 44)
            .padding(.trailing, 4)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private var isCurrentLocation: Bool {
        place?.source == .currentLocation || (endpoint == .origin && place == nil)
    }

    private var mode: TransportMode { place?.modes.primaryMode ?? .unknown }

    private func performSwap() {
        swap()
        swapFeedback.toggle()
    }
}
