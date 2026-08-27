import SwiftUI

/// A compact capsule badge showing the live/scheduled/transfer/missed status
/// of a ``RouteOption``.
struct RouteOptionBadge: View {
    let status: RouteOptionStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(status.displayText)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(foregroundColor)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
    }

    private var symbolName: String {
        switch status {
        case .viable: "checkmark.circle.fill"
        case .partiallyLive, .scheduledOnly: "clock.badge.exclamationmark"
        case .atRisk: "exclamationmark.triangle.fill"
        case .connectionMayBeMissed: "xmark.circle.fill"
        case .missed, .cancelled: "xmark.circle.fill"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .viable: .green
        case .partiallyLive, .scheduledOnly: .orange
        case .atRisk: .orange
        case .connectionMayBeMissed: .red
        case .missed, .cancelled: .red
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .viable: .green.opacity(0.14)
        case .partiallyLive, .scheduledOnly: .orange.opacity(0.14)
        case .atRisk: .orange.opacity(0.14)
        case .connectionMayBeMissed: .red.opacity(0.14)
        case .missed, .cancelled: .red.opacity(0.14)
        }
    }
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        HStack {
            RouteOptionBadge(status: .viable)
            RouteOptionBadge(status: .partiallyLive)
            RouteOptionBadge(status: .scheduledOnly)
            RouteOptionBadge(status: .atRisk)
            RouteOptionBadge(status: .connectionMayBeMissed)
            RouteOptionBadge(status: .missed)
            RouteOptionBadge(status: .cancelled)
        }
        .padding()
    }
#endif
