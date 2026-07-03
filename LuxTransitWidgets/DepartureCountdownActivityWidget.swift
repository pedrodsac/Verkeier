import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct DepartureCountdownActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            DepartureLockScreenView(context: context)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(Color.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.lineName)
                        .font(.title3.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusText)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.destination)
                            .font(.subheadline.weight(.semibold))
                        Text(context.attributes.stopName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.attributes.lineName)
                    .font(.caption.weight(.bold))
            } compactTrailing: {
                if let departureDate = context.state.displayDepartureDate {
                    Text(timerInterval: .now ... departureDate, countsDown: true)
                        .monospacedDigit()
                } else {
                    Image(systemName: "clock")
                }
            } minimal: {
                Image(systemName: context.state.isCancelled ? "xmark.octagon.fill" : "bus.fill")
            }
        }
    }
}

private struct DepartureLockScreenView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Text(context.attributes.lineName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 42)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.destination)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.attributes.stopName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let departureDate = context.state.displayDepartureDate {
                    Text(timerInterval: .now ... departureDate, countsDown: true)
                        .font(.headline.monospacedDigit())
                } else {
                    Text("Time unknown")
                        .font(.caption)
                }
                Text(context.state.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
        }
        .padding()
    }

    private var statusColor: Color {
        if context.state.isCancelled { return .red }
        if let delay = context.state.delayMinutes, delay > 0 { return .orange }
        return .secondary
    }
}
