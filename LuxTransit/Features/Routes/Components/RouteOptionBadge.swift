import SwiftUI

/// A compact capsule badge showing the live/scheduled/at-risk/missed status
/// of a ``RouteOption``.
struct RouteOptionBadge: View {
    let status: RouteOptionStatus

    var body: some View {
        Text(status.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .viable: .green
        case .scheduledOnly: .secondary
        case .atRisk: .orange
        case .missed, .cancelled: .red
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .viable: .green.opacity(0.14)
        case .scheduledOnly: .secondary.opacity(0.12)
        case .atRisk: .orange.opacity(0.14)
        case .missed, .cancelled: .red.opacity(0.14)
        }
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    HStack {
        RouteOptionBadge(status: .viable)
        RouteOptionBadge(status: .scheduledOnly)
        RouteOptionBadge(status: .atRisk)
        RouteOptionBadge(status: .missed)
        RouteOptionBadge(status: .cancelled)
    }
    .padding()
}
#endif
