import SwiftUI

/// A compact capsule badge showing the live/scheduled/transfer/missed status
/// of a ``RouteOption``.
struct RouteOptionStrip: View {
	let status: RouteOptionStatus
	
	var body: some View {
		HStack(spacing: 3) {
			Spacer()
			Image(systemName: symbolName)
				.symbolRenderingMode(.hierarchical)
				.imageScale(.small)
				.accessibilityHidden(true)
			Text(status.displayText)
			Spacer()
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(foregroundColor)
		.lineLimit(1)
		.padding(8)
	}
	
	private var symbolName: String {
		switch status {
			case .viable: "checkmark.circle.fill"
			case .delayed: "clock.badge.exclamationmark"
			case .partiallyLive, .scheduledOnly: "clock.badge.exclamationmark"
			case .atRisk: "exclamationmark.triangle.fill"
			case .connectionMayBeMissed: "xmark.circle.fill"
			case .missed, .cancelled: "xmark.circle.fill"
		}
	}
	
	private var foregroundColor: Color {
		switch status {
			case .viable: .green
			case .delayed: .orange
			case .partiallyLive: .yellow
			case .scheduledOnly: .orange
			case .atRisk: .orange
			case .connectionMayBeMissed: .red
			case .missed, .cancelled: .red
		}
	}
	
	private var backgroundColor: Color {
		switch status {
			case .viable: .green.opacity(0.14)
			case .delayed: .orange.opacity(0.14)
			case .partiallyLive: .yellow.opacity(0.14)
			case .scheduledOnly: .orange.opacity(0.14)
			case .atRisk: .orange.opacity(0.14)
			case .connectionMayBeMissed: .red.opacity(0.14)
			case .missed, .cancelled: .red.opacity(0.14)
		}
	}
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        HStack {
            RouteOptionStrip(status: .viable)
            RouteOptionStrip(status: .delayed)
            RouteOptionStrip(status: .partiallyLive)
            RouteOptionStrip(status: .scheduledOnly)
            RouteOptionStrip(status: .atRisk)
            RouteOptionStrip(status: .connectionMayBeMissed)
            RouteOptionStrip(status: .missed)
            RouteOptionStrip(status: .cancelled)
        }
        .padding()
    }
#endif
