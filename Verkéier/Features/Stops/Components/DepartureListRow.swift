import SwiftUI

struct DepartureListRow: View {
    let departure: Departure
    var isTracked: Bool = false
    var isLastOfDay: Bool = false
    var showsControls: Bool = true
    var activeReminder: SharedTrackedDepartureReminder?
    var startTrackingDeparture: () -> Void = {}
    var stopTrackingDeparture: () -> Void = {}
    var scheduleReminder: (Int) -> Void = { _ in }
    var cancelReminder: () -> Void = {}

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: transportIcon)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(departure.lineName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 52, minHeight: 34)
            .padding(.horizontal, 7)
            .background(
                lineColor.gradient,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 4) {
                OverflowMarqueeText(
                    text: departure.destination.isEmpty ? "Destination unknown" : departure.destination,
                    font: .body.weight(.semibold)
                )

                if isLastOfDay {
                    Text("Last service today")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    departureTimeView
                    if let platform = departure.platform, !platform.isEmpty {
						Divider()
							.frame(height: 10)
                        Text("Platform \(platform)")
                    }

                    Spacer()
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if departure.hasPlatformChange, let previous = departure.previousPlatform {
                    Label("Platform changed from \(previous)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if let continuesAs = departure.continuesAs {
                    Label("Continues as \(continuesAs) — no change needed", systemImage: "arrow.triangle.merge")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let occupancy = departure.occupancy {
                    Label(occupancy.displayText, systemImage: occupancy.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .layoutPriority(0)

            DepartureTimingStatus(
                countdownText: countdownText,
                countdownColor: countdownColor,
                statusBadge: statusBadge,
                statusColor: statusColor
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if showsControls {
                Button(action: isTracked ? stopTrackingDeparture : startTrackingDeparture) {
                    Label(
                        isTracked ? "Stop tracking departure" : "Track departure",
                        systemImage: isTracked ? "timer.circle.fill" : "timer"
                    )
                }

                reminderContextMenu
            }
        }
		.swipeActions(edge: .trailing) {
			if isTracked {
				Button("Stop Tracking") {
					stopTrackingDeparture()
				}
			}
		}
        .accessibilityElement(children: .combine)
    }

    private var reminderContextMenu: some View {
        Menu {
            let defaultMinutes = preferences.defaultReminderLeadTimeMinutes
            Button("Remind \(defaultMinutes) min before (default)") {
                scheduleReminder(defaultMinutes)
            }
            ForEach(AppPreferences.reminderLeadTimeOptions.filter { $0 != defaultMinutes }, id: \.self) { minutes in
                Button("Remind \(minutes) min before") {
                    scheduleReminder(minutes)
                }
            }
            if isReminderActive {
                Button("Cancel reminder", role: .destructive, action: cancelReminder)
            }
        } label: {
            Label(
                isReminderActive ? "Change departure reminder" : "Add departure reminder",
                systemImage: isReminderActive ? "bell.badge.fill" : "bell"
            )
        }
    }

    private var departureDate: Date? {
        departure.realtimeDeparture ?? departure.scheduledDeparture
    }

    private var departureTimeText: String {
        departureDate?.formatted(date: .omitted, time: .shortened) ?? "Time unknown"
    }

    @ViewBuilder
    private var departureTimeView: some View {
        if case .delayed = departure.status,
           let scheduledDeparture = departure.scheduledDeparture,
           let realtimeDeparture = departure.realtimeDeparture {
            Text(formattedTime(scheduledDeparture))
                .strikethrough()
                .foregroundStyle(.secondary)
            Text(formattedTime(realtimeDeparture))
                .foregroundStyle(.orange)
        } else {
            Text(departureTimeText)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var countdownText: String {
        guard let departureDate else { return "—" }
        let minutes = SharedDepartureTiming.countdownMinutes(until: departureDate, from: .now)
        if minutes == 0 { return "Now" }
        if minutes < 90 { return "\(minutes)m" }
        return departureDate.formatted(date: .omitted, time: .shortened)
    }

    private var statusBadge: String? {
        switch departure.status {
        case .cancelled: "Cancelled"
        case let .delayed(minutes): "+\(minutes)"
        case .onTime: "On time"
        case .scheduled, .unknown: nil
        }
    }

    private var countdownColor: Color {
        switch departure.status {
        case .cancelled: .red
        case .delayed: .orange
        default: .primary
        }
    }

    private var statusColor: Color {
        switch departure.status {
        case .delayed: .orange
        case .cancelled: .red
        case .onTime: .green
        case .scheduled, .unknown: .secondary
        }
    }

    private var lineColor: Color {
        transportKind.color
    }

    private var isReminderActive: Bool {
        activeReminder?.departureId == departure.id
    }

    private var transportIcon: String {
        transportKind.icon
    }

    private var transportKind: DepartureTransportKind {
        DepartureTransportKind(lineName: departure.lineName)
    }
}

/// Shows long one-line labels as a slow, readable marquee instead of hiding
/// the destination behind a tail ellipsis. Shared by departure and route rows.
/// The duplicate label makes the loop seamless, while the mask softens both
/// edges of the visible window.
struct OverflowMarqueeText: View {
    let text: String
    let font: Font
    var initialLeadingInset: CGFloat = 0
    /// Lets a parent that already measured the available space select the
    /// scrolling branch. This avoids a second, slightly different width
    /// calculation falling back to tail truncation.
    var forceScroll = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentWidth: CGFloat = 0
    @State private var isScrolling = false

    private let copySpacing: CGFloat = 28
    private let edgeFade: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let shouldScroll = contentWidth > 0
                && !reduceMotion
                && (forceScroll || contentWidth > proxy.size.width + 1)

            ZStack(alignment: .leading) {
                if shouldScroll {
                    HStack(spacing: copySpacing) {
                        label
                        label
                            .accessibilityHidden(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    // Keep the same leading inset when the duplicate copy
                    // enters the loop. The text may still travel underneath
                    // the overlapping line badge while moving, but it never
                    // snaps to a different horizontal alignment at the seam.
                    .offset(
                        x: isScrolling
                            ? -(contentWidth + copySpacing) + initialLeadingInset
                            : initialLeadingInset
                    )
                    .animation(
                        .linear(duration: scrollDuration)
                            .delay(0.9)
                            .repeatForever(autoreverses: false),
                        value: isScrolling
                    )
                } else {
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, initialLeadingInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Expand to the row's proposed height so the moving label is
            // centered vertically instead of staying at its intrinsic top.
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: Alignment(horizontal: .leading, vertical: .center)
            )
            .clipped()
            .mask {
                if shouldScroll {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 1 - edgeFadeLocation),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Rectangle().fill(.black)
                }
            }
            .onAppear {
                restartScrolling(if: shouldScroll)
            }
            .onChange(of: shouldScroll) { _, newValue in
                restartScrolling(if: newValue)
            }
            .onChange(of: text) { _, _ in
                restartScrolling(if: shouldScroll)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: MarqueeTextWidthKey.self, value: proxy.size.width)
                    }
                }
                .hidden()
                .allowsHitTesting(false)
        }
        .onPreferenceChange(MarqueeTextWidthKey.self) { width in
            guard abs(contentWidth - width) > 0.5 else { return }
            contentWidth = width
        }
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var edgeFadeLocation: CGFloat {
        // Keep the fade subtle for short rows while still making the moving
        // text feel naturally clipped at the card edges.
        min(0.14, edgeFade / max(contentWidth + copySpacing, 1))
    }

    private var scrollDuration: Double {
        // About 51 points/second keeps stop names readable without making a
        // long destination take an unreasonably long time to reveal itself.
        max(7, Double(contentWidth + copySpacing + initialLeadingInset) / 51)
    }

    private func restartScrolling(if shouldScroll: Bool) {
        isScrolling = false
        guard shouldScroll else { return }

        // Let SwiftUI render the resting position before moving to the end;
        // this gives the first part of the destination a readable pause.
        DispatchQueue.main.async {
            guard !reduceMotion else { return }
            isScrolling = true
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DepartureTimingStatus: View {
    let countdownText: String
    let countdownColor: Color
    let statusBadge: String?
    let statusColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(countdownText)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(countdownColor)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(Animation.respectingReduceMotion(.snappy, reduceMotion), value: countdownText)

            if let statusBadge {
                HStack(spacing: 4) {
                    Text(statusBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(alignment: .trailing)
    }
}

enum DepartureTransportKind {
    case bus
    case tram
    case train

    /// Infers the kind from a public line label, e.g. `"T1"` → tram.
    init(lineName: String) {
        let line = lineName.uppercased()
        if line.hasPrefix("T") {
            self = .tram
        } else if line.hasPrefix("R") || line.hasPrefix("RE") || line.hasPrefix("IC") {
            self = .train
        } else {
            self = .bus
        }
    }

    var color: Color {
        switch self {
        case .tram: .orange
        case .train: .red
        case .bus: .blue
        }
    }

    var icon: String {
        switch self {
        case .tram: "tram.fill"
        case .train: "train.side.front.car"
        case .bus: "bus.fill"
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureListRow(
        departure: Departure(
            id: "dep-1",
            stopId: "200209001",
            lineName: "16",
            destination: "Bertrange, Belle Étoile",
            scheduledDeparture: .now,
            realtimeDeparture: .now,
            delayMinutes: 0,
            platform: "1",
            dataSource: .mock
        )
    )
    .padding(.horizontal, 12)
}
