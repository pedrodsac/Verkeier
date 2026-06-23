import SwiftUI

// MARK: - RouteTimelineSummaryCard

/// A summary card at the top of the route timeline showing the chosen option's
/// ribbon, total duration, and arrival time.
struct RouteTimelineSummaryCard: View {
    let option: RouteOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: time range + duration
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(timeRangeText)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)

                Text("  ·  \(durationText)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                RouteOptionBadge(status: option.status(at: .now))
            }

            // Mode/line ribbon
            RouteRibbon(legs: option.plan.legs)

            // Footer: transfer count + distance
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            .background.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.blue.opacity(0.35), lineWidth: 1)
        }
    }

    private var timeRangeText: String {
        let dep = option.firstTransitDepartureTime
        let arr = option.arrivalTime
        switch (dep, arr) {
        case let (.some(d), .some(a)):
            return "\(d.formatted(date: .omitted, time: .shortened)) – \(a.formatted(date: .omitted, time: .shortened))"
        case let (.some(d), .none):
            return d.formatted(date: .omitted, time: .shortened)
        default:
            return "Scheduled route"
        }
    }

    private var durationText: String {
        let minutes = max(1, Int(((option.plan.expectedTravelTime ?? 0) / 60).rounded()))
        return "\(minutes) min"
    }

    private var footerText: String {
        let transfers = switch option.transferCount {
        case 0: "Direct"
        case 1: "1 transfer"
        default: "\(option.transferCount) transfers"
        }
        let meters = option.plan.distanceMeters ?? 0
        let dist = meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
        return "\(transfers)  ·  \(dist)"
    }
}

// MARK: - RouteLegList

/// The place-centric vertical timeline for a selected route: an alternating list
/// of station rows (dots) and segment rows (walk / transfer / ride), joined by a
/// continuous rail. Flattened from the legs by ``RouteTimelineBuilder``.
struct RouteLegList: View {
    let legs: [RoutePlan.Leg]

    private var items: [RouteTimelineItem] {
        RouteTimelineBuilder.items(from: legs)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case let .place(node):
                        TimelinePlaceRow(node: node)
                    case let .segment(node):
                        TimelineSegmentRow(node: node)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Place row

private struct TimelinePlaceRow: View {
    let node: PlaceNode

    var body: some View {
        HStack(alignment: .center, spacing: RouteTimelineLayout.columnSpacing) {
            TimelineRail(above: node.railAbove, below: node.railBelow, dot: true)
                .frame(width: RouteTimelineLayout.railColumnWidth)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.time?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if node.showsDelayBadge {
                    Text(delayText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(delayColor)
                        .monospacedDigit()
                }
            }
            .frame(width: RouteTimelineLayout.timeColumnWidth, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(node.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let platform = node.platform, !platform.isEmpty {
                    Text("Plat. \(platform)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: RouteTimelineLayout.placeRowHeight)
        .accessibilityElement(children: .combine)
    }

    private var delayText: String {
        "+\(node.delayMinutes ?? 0)"
    }

    private var delayColor: Color {
        switch node.liveStatus {
        case .live: .green
        case .delayed: .orange
        case .cancelled: .red
        case .scheduled, .unknown: .secondary
        }
    }
}

// MARK: - Segment row

private struct TimelineSegmentRow: View {
    let node: SegmentNode

    var body: some View {
        HStack(alignment: .center, spacing: RouteTimelineLayout.columnSpacing) {
            TimelineRail(above: node.rail, below: node.rail, dot: false)
                .frame(width: RouteTimelineLayout.railColumnWidth)

            Color.clear
                .frame(width: RouteTimelineLayout.timeColumnWidth, height: 0)

            VStack(alignment: .leading, spacing: 4) {
                content
                if let warning = node.transferWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 10)

            Spacer(minLength: 0)
        }
        .frame(minHeight: RouteTimelineLayout.segmentRowHeight)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .transit:
            HStack(spacing: 8) {
                TimelineLineBadge(text: node.badgeText ?? node.mode.displayName, mode: node.mode)
                if let headsign = node.headsign, !headsign.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(headsign)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            if let mins = node.durationMinutes {
                Text("\(mins) min")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .walk, .transfer:
            Label {
                Text(walkText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }

    private var walkText: String {
        let mins = node.durationMinutes
        if node.kind == .transfer {
            return mins.map { "Transfer: \($0) min" } ?? "Transfer"
        }
        let dist = node.distanceMeters.map(distanceText)
        switch (dist, mins) {
        case let (.some(d), .some(m)): return "Walk: \(d) (\(m) min)"
        case let (.some(d), .none): return "Walk: \(d)"
        case let (.none, .some(m)): return "Walk: \(m) min"
        case (.none, .none): return "Walk"
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
    }
}

// MARK: - Rail

/// Draws one row's slice of the connecting rail: an upper half (`above`) and a
/// lower half (`below`), each solid or dotted per ``RailStyle``, with an
/// optional station dot centred on top. With `VStack(spacing: 0)` the per-row
/// slices join into one continuous rail.
private struct TimelineRail: View {
    let above: RailStyle?
    let below: RailStyle?
    let dot: Bool

    var body: some View {
        GeometryReader { proxy in
            let midX = proxy.size.width / 2
            let midY = proxy.size.height / 2
            ZStack {
                if let above {
                    railLine(above, from: CGPoint(x: midX, y: 0), to: CGPoint(x: midX, y: midY))
                }
                if let below {
                    railLine(below, from: CGPoint(x: midX, y: midY), to: CGPoint(x: midX, y: proxy.size.height))
                }
                if dot {
                    Circle()
                        .fill(dotColor)
                        .frame(width: RouteTimelineLayout.dotSize, height: RouteTimelineLayout.dotSize)
                        .position(x: midX, y: midY)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func railLine(_ style: RailStyle, from: CGPoint, to: CGPoint) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            color(for: style),
            style: StrokeStyle(
                lineWidth: RouteTimelineLayout.railWidth,
                lineCap: .round,
                dash: isDashed(style) ? [1, RouteTimelineLayout.railWidth * 2.5] : []
            )
        )
    }

    private func color(for style: RailStyle) -> Color {
        switch style {
        case let .transit(mode): mode.tint
        case .walk: .green
        }
    }

    private func isDashed(_ style: RailStyle) -> Bool {
        if case .walk = style { return true }
        return false
    }

    private var dotColor: Color {
        if let above { return color(for: above) }
        if let below { return color(for: below) }
        return .secondary
    }
}

// MARK: - Line badge

/// A solid line badge — white label on the mode's gradient.
// ponytail: small dup of RouteRibbon.TransitBadge; extract to shared only if a third user appears.
private struct TimelineLineBadge: View {
    let text: String
    let mode: TransportMode

    var body: some View {
        Text(text)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                mode.tint.gradient,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

// MARK: - Layout constants

private enum RouteTimelineLayout {
    static let timeColumnWidth: CGFloat = 52
    static let railColumnWidth: CGFloat = 24
    static let columnSpacing: CGFloat = 10
    static let railWidth: CGFloat = 2.5
    static let dotSize: CGFloat = 11
    static let placeRowHeight: CGFloat = 30
    static let segmentRowHeight: CGFloat = 44
}

// MARK: - Previews

#if DEBUG

    private let previewOrigin = LocationPoint(
        id: "origin",
        name: "Current Location",
        latitude: 49.6116,
        longitude: 6.1319
    )
    private let previewHamilius = LocationPoint(id: "hamilius", name: "Hamilius", latitude: 49.6111, longitude: 6.1275)
    private let previewKirchberg = LocationPoint(
        id: "kirchberg",
        name: "Kirchberg P+R",
        latitude: 49.6260,
        longitude: 6.1600
    )
    private let previewLuxexpo = LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746)

    private let previewWalkLeg = RoutePlan.Leg(
        id: "walk1",
        mode: .walking,
        instruction: "Walk to Hamilius",
        transportKind: .walking,
        origin: previewOrigin,
        destination: previewHamilius,
        departureTime: Date(),
        arrivalTime: Date().addingTimeInterval(4 * 60),
        distanceMeters: 320
    )

    private let previewTramLeg = RoutePlan.Leg(
        id: "tram1",
        mode: .tram,
        instruction: "Take tram T1 toward Luxexpo",
        transportKind: .transit,
        routeName: "T1",
        origin: previewHamilius,
        destination: previewKirchberg,
        departureTime: Date().addingTimeInterval(6 * 60),
        arrivalTime: Date().addingTimeInterval(14 * 60),
        realtimeDepartureTime: Date().addingTimeInterval(7 * 60),
        realtimeArrivalTime: Date().addingTimeInterval(15 * 60),
        platform: "2",
        delayMinutes: 1,
        liveStatus: .live
    )

    private let previewBusLeg = RoutePlan.Leg(
        id: "bus1",
        mode: .bus,
        instruction: "Take bus 16 toward Luxexpo",
        transportKind: .transit,
        routeName: "16",
        origin: previewKirchberg,
        destination: previewLuxexpo,
        departureTime: Date().addingTimeInterval(16 * 60),
        arrivalTime: Date().addingTimeInterval(22 * 60),
        liveStatus: .scheduled,
        transferWarning: "Only 1 min to transfer"
    )

    private let previewFinalWalkLeg = RoutePlan.Leg(
        id: "walk2",
        mode: .walking,
        instruction: "Walk to Luxexpo entrance",
        transportKind: .walking,
        origin: previewLuxexpo,
        destination: LocationPoint(id: "dest", name: "Luxexpo", latitude: 49.6335, longitude: 6.1755),
        departureTime: Date().addingTimeInterval(22 * 60),
        arrivalTime: Date().addingTimeInterval(24 * 60),
        distanceMeters: 110
    )

    private let previewTramPlan = RoutePlan(
        id: "tram-plan",
        origin: previewOrigin,
        destination: previewLuxexpo,
        expectedTravelTime: 24 * 60,
        distanceMeters: 4500,
        legs: [previewWalkLeg, previewTramLeg, previewBusLeg, previewFinalWalkLeg],
        dataSource: .mock
    )

    private let previewTramOption = RouteOption(
        id: "tram-route",
        plan: previewTramPlan,
        mapOverlay: nil
    )

    private let previewDelayedOption = RouteOption(
        id: "delayed-route",
        plan: RoutePlan(
            id: "delayed-plan",
            origin: previewOrigin,
            destination: previewLuxexpo,
            expectedTravelTime: 30 * 60,
            distanceMeters: 4800,
            legs: [
                previewWalkLeg,
                RoutePlan.Leg(
                    id: "delayed-tram",
                    mode: .tram,
                    instruction: "Take tram T1 toward Luxexpo",
                    transportKind: .transit,
                    routeName: "T1",
                    origin: previewHamilius,
                    destination: previewLuxexpo,
                    departureTime: Date().addingTimeInterval(6 * 60),
                    arrivalTime: Date().addingTimeInterval(28 * 60),
                    realtimeDepartureTime: Date().addingTimeInterval(12 * 60),
                    realtimeArrivalTime: Date().addingTimeInterval(30 * 60),
                    delayMinutes: 6,
                    liveStatus: .delayed
                )
            ],
            dataSource: .mock
        ),
        mapOverlay: nil
    )

    #Preview("Summary Card – Live", traits: .sizeThatFitsLayout) {
        RouteTimelineSummaryCard(option: previewTramOption)
            .padding()
    }

    #Preview("Summary Card – Delayed", traits: .sizeThatFitsLayout) {
        RouteTimelineSummaryCard(option: previewDelayedOption)
            .padding()
    }

    #Preview("Timeline – Walk + Tram + Bus + Walk", traits: .sizeThatFitsLayout) {
        RouteLegList(legs: [previewWalkLeg, previewTramLeg, previewBusLeg, previewFinalWalkLeg])
            .padding()
    }

    #Preview("Timeline – Delayed", traits: .sizeThatFitsLayout) {
        RouteLegList(legs: previewDelayedOption.plan.legs)
            .padding()
    }

#endif
