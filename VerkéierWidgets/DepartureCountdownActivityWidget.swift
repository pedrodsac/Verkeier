import ActivityKit
import SwiftUI
import WidgetKit

struct DepartureCountdownActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            DepartureLockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.accentColor)
                .widgetURL(TransitDeepLink.showDepartures(stopId: context.attributes.stopId).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityLineBadge(line: context.attributes.lineName, compact: false)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        ActivityExpandedDepartureCountdown(state: context.state)
                        ActivityStatusLabel(state: context.state, prominent: true)
							.padding(.trailing, 4)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
					.padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.destination)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                        Text(context.attributes.stopName.stationDisplayName)
                            .lineLimit(1)
                            if let platform = context.attributes.platform, !platform.isEmpty {
                                Text("· Platform \(platform)")
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
					.padding(.top, -10)
                }
            } compactLeading: {
                ActivityLineBadge(line: context.attributes.lineName, compact: true)
            } compactTrailing: {
                ActivityCompactDepartureCountdown(state: context.state, compact: true)
            } minimal: {
                ZStack {
                    Circle().fill(lineColor(context.attributes.lineName))
                    Image(systemName: context.state.isCancelled ? "xmark" : "tram.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .widgetURL(TransitDeepLink.showDepartures(stopId: context.attributes.stopId).url)
            .keylineTint(lineColor(context.attributes.lineName))
        }
    }
}

private struct ActivityCompactDepartureCountdown: View {
	let compact: Bool
    let state: DepartureActivityAttributes.ContentState

	init(state: DepartureActivityAttributes.ContentState, compact: Bool = false) {
		self.state = state
		self.compact = compact
	}
	
    var body: some View {
        Group {
            if state.isCancelled {
                Image(systemName: "xmark")
            } else if let date = state.displayDepartureDate {
                Text(timerInterval: Date.now...max(date, Date.now), countsDown: true)
            } else {
                Text("—")
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(statusColor)
        .lineLimit(1)
		.frame(width: compact ? 40 : 50, alignment: .trailing)
    }

    private var statusColor: Color {
        if state.isCancelled { return .red }
        if (state.delayMinutes ?? 0) > 0 { return .orange }
        if state.statusText == "On time" { return .green }
        return .secondary
    }
}

private struct DepartureLockScreenView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ActivityLineBadge(line: context.attributes.lineName, compact: false, roundedSquare: true)

			VStack(alignment: .leading, spacing: 5) {
				HStack(spacing: 5) {
					Text(context.attributes.destination)
						.font(.headline.weight(.semibold).width(.condensed))
						.lineLimit(1)

					Spacer(minLength: 0)

					ActivityCountdown(state: context.state, prominent: true)
						.multilineTextAlignment(.trailing)
						.frame(width: 50, alignment: .trailing)
				}

				HStack(spacing: 5) {
					HStack(spacing: 5) {
                        Text(context.attributes.stopName.stationDisplayName)

						if let platform = context.attributes.platform, !platform.isEmpty {
							Text("· Platform \(platform)")
						}
					}
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)

					Spacer(minLength: 0)

					ActivityStatusLabel(state: context.state)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLineBadge: View {
    let line: String
    let compact: Bool
    var roundedSquare = false

    private var size: CGSize {
        compact ? CGSize(width: 60, height: 25) : CGSize(width: 58, height: 58)
    }

    // These radii mirror the surrounding system surfaces after their visual inset:
    // inner radius + surrounding inset = outer radius.
    private var cornerRadius: CGFloat {
		compact ? .infinity : 16
    }

    var body: some View {
        Text(line)
			.font(compact ? .caption2.weight(.heavy) : .title2.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height)
		.background {
            if compact || roundedSquare {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(lineColor(line).gradient)
            } else {
                Circle()
                    .fill(lineColor(line).gradient)
            }
        }
    }
}

private struct ActivityExpandedDepartureCountdown: View {
    let state: DepartureActivityAttributes.ContentState

    var body: some View {
        Group {
            if let date = state.displayDepartureDate {
                Text(timerInterval: Date.now...max(date, Date.now), countsDown: true)
            } else {
                Text("—")
            }
        }
        .font(.headline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(state.isCancelled ? .secondary : .primary)
        .lineLimit(1)
		.frame(width: 50)
    }
}

private struct ActivityCountdown: View {
    let state: DepartureActivityAttributes.ContentState
    let prominent: Bool

    var body: some View {
        Group {
            if state.isCancelled {
                Image(systemName: "xmark.circle.fill")
            } else if let date = state.displayDepartureDate {
                Text(timerInterval: Date.now...max(date, Date.now), countsDown: true)
                    .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .font(prominent ? .headline.weight(.bold) : .caption2.weight(.bold))
        .foregroundStyle(countdownColor)
        .lineLimit(1)
    }

    private var countdownColor: Color {
        if state.isCancelled { return .red }
        if (state.delayMinutes ?? 0) > 0 { return .orange }
        return .primary
    }
}

private struct ActivityStatusLabel: View {
    let state: DepartureActivityAttributes.ContentState
    var prominent = false

    var body: some View {
        Text(state.statusText)
            .font(prominent ? .caption.weight(.bold) : .caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var color: Color {
        if state.isCancelled { return .red }
        if (state.delayMinutes ?? 0) > 0 { return .orange }
        if state.statusText == "On time" { return .green }
        return .secondary
    }
}

private func lineColor(_ line: String) -> Color {
    let name = line.uppercased()
    if name.hasPrefix("T") { return .orange }
    if name.range(of: #"^\d+$"#, options: .regularExpression) != nil { return .blue }
    return .red
}

#Preview("Line 16 · Lock Screen", as: .content, using: DepartureActivityAttributes.preview,
         widget: { DepartureCountdownActivityWidget() }, contentStates: { DepartureActivityAttributes.previewState })
#Preview("Line 16 · Dynamic Island", as: .dynamicIsland(.expanded), using: DepartureActivityAttributes.preview,
         widget: { DepartureCountdownActivityWidget() }, contentStates: { DepartureActivityAttributes.previewState })
#Preview("Line 16 · Compact Island", as: .dynamicIsland(.compact), using: DepartureActivityAttributes.preview,
         widget: { DepartureCountdownActivityWidget() }, contentStates: { DepartureActivityAttributes.previewState })

private extension DepartureActivityAttributes {
    static var preview: Self {
        Self(
            departureId: "preview-line-16",
            stopId: "hamilius",
            stopName: "Hamilius",
            lineName: "16",
            destination: "Findel - Luxembourg Airport",
            platform: nil
        )
    }

    static var previewState: ContentState {
        let departure = Date(timeIntervalSinceNow: 5 * 60 + 30)
        return ContentState(
            scheduledDeparture: departure,
            realtimeDeparture: departure,
            delayMinutes: 0,
            isCancelled: false,
            lastUpdated: .now,
            staleAfter: Date(timeIntervalSinceNow: 90)
        )
    }
}
