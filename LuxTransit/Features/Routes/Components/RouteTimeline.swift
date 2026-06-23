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
        let transfers: String
        switch option.transferCount {
        case 0: transfers = "Direct"
        case 1: transfers = "1 transfer"
        default: transfers = "\(option.transferCount) transfers"
        }
        let meters = option.plan.distanceMeters ?? 0
        let dist = meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
        return "\(transfers)  ·  \(dist)"
    }
}

// MARK: - RouteLegList

/// The vertical-timeline leg list for a selected route, with a connecting rail
/// drawn between per-leg markers using a preference-key layout pass.
struct RouteLegList: View {
    let legs: [RoutePlan.Leg]

    @State private var markerCenters: [String: CGFloat] = [:]

    private var displayLegs: [RoutePlan.Leg] {
        legs.filter { $0.instruction != nil || $0.distanceMeters != nil }
    }

    var body: some View {
        if !displayLegs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    timelineRail(for: displayLegs)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayLegs) { leg in
                            RouteLegRow(leg: leg)
                        }
                    }
                }
                .coordinateSpace(.named(RouteLegTimelineLayout.coordinateSpace))
                .onPreferenceChange(TimelineMarkerCenterPreferenceKey.self) { centers in
                    markerCenters = centers
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func timelineRail(for displayLegs: [RoutePlan.Leg]) -> some View {
        let segments = railSegments(for: displayLegs)
        if !segments.isEmpty {
            Path { path in
                for segment in segments {
                    path.move(to: CGPoint(x: RouteLegTimelineLayout.markerCenterX, y: segment.start))
                    path.addLine(to: CGPoint(x: RouteLegTimelineLayout.markerCenterX, y: segment.end))
                }
            }
            .stroke(
                Color(uiColor: .separator).opacity(0.45),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
        }
    }

    private func railSegments(for legs: [RoutePlan.Leg]) -> [(start: CGFloat, end: CGFloat)] {
        let centers = legs.compactMap { markerCenters[$0.id] }
        guard centers.count > 1 else { return [] }
        return zip(centers.dropLast(), centers.dropFirst()).compactMap { curr, next in
            let start = curr + RouteLegTimelineLayout.markerRadius + RouteLegTimelineLayout.railGap
            let end = next - RouteLegTimelineLayout.markerRadius - RouteLegTimelineLayout.railGap
            guard end > start else { return nil }
            return (start, end)
        }
    }
}

// MARK: - RouteLegRow

struct RouteLegRow: View {
    let leg: RoutePlan.Leg

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timelineMarker
                .frame(width: RouteLegTimelineLayout.markerColumnWidth, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                // Instruction or mode name
                instructionRow

                // Time range
                if let timeText {
                    Text(timeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Platform pill
                if let platform = leg.platform, !platform.isEmpty {
                    Text("Platform \(platform)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(markerColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            markerColor.opacity(0.12),
                            in: Capsule()
                        )
                }

                // Live status
                if leg.liveStatus != .scheduled {
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                // Transfer warning
                if let warning = leg.transferWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }

                // Walking distance
                if let meters = leg.distanceMeters, leg.transportKind == .walking {
                    Text(distanceText(meters))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Instruction row

    @ViewBuilder
    private var instructionRow: some View {
        if let routeName = leg.routeName, leg.transportKind == .transit {
            // Transit leg: line chip first, then the destination — the raw
            // instruction already repeats the line number, so don't show both.
            HStack(alignment: .center, spacing: 6) {
                Text(routeName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        markerColor.gradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )

                Text(transitHeadline)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } else {
            Text(leg.instruction ?? leg.transportKind.displayName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Timeline marker

    private var timelineMarker: some View {
        ZStack {
            Circle()
                .fill(markerColor.opacity(0.16))
            Circle()
                .stroke(markerColor.opacity(0.85), lineWidth: 2)
            Image(systemName: leg.mode.symbolName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(markerColor)
        }
        .frame(
            width: RouteLegTimelineLayout.markerSize,
            height: RouteLegTimelineLayout.markerSize
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TimelineMarkerCenterPreferenceKey.self,
                    value: [
                        leg.id: proxy.frame(
                            in: .named(RouteLegTimelineLayout.coordinateSpace)
                        ).midY
                    ]
                )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private var markerColor: Color {
        leg.transportKind == .walking ? .green : leg.mode.tint
    }

    /// Text shown after the line chip on a transit row. Prefers the destination
    /// stop ("to Kirchberg"); falls back to the mode name when it's unknown.
    private var transitHeadline: String {
        if let name = leg.destination.name, !name.isEmpty {
            return "to \(name)"
        }
        return leg.mode.displayName
    }

    private var timeText: String? {
        let dep = leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
        let arr = leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
        guard let dep, let arr else { return nil }
        return "\(dep.formatted(date: .omitted, time: .shortened)) – \(arr.formatted(date: .omitted, time: .shortened))"
    }

    private var statusText: String {
        if let delay = leg.delayMinutes, delay > 0 {
            return "\(leg.liveStatus.displayText)  +\(delay) min"
        }
        return leg.liveStatus.displayText
    }

    private var statusColor: Color {
        switch leg.liveStatus {
        case .live: .green
        case .delayed: .orange
        case .cancelled: .red
        case .scheduled, .unknown: .secondary
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
    }
}

// MARK: - Layout constants

enum RouteLegTimelineLayout {
    static let markerColumnWidth: CGFloat = 28
    static let markerSize: CGFloat = 24
    static let markerRadius = markerSize / 2
    static let markerCenterX = markerColumnWidth / 2
    static let railGap: CGFloat = 6
    static let coordinateSpace = "RouteLegTimelineCoordinateSpace"
}

// MARK: - Preference key

struct TimelineMarkerCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, next in next }
    }
}

// MARK: - Previews

#if DEBUG

private let previewOrigin = LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319)
private let previewHamilius = LocationPoint(id: "hamilius", name: "Hamilius", latitude: 49.6111, longitude: 6.1275)
private let previewKirchberg = LocationPoint(id: "kirchberg", name: "Kirchberg P+R", latitude: 49.6260, longitude: 6.1600)
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

#Preview("Leg List – Walk + Tram + Bus + Walk", traits: .sizeThatFitsLayout) {
    RouteLegList(legs: [previewWalkLeg, previewTramLeg, previewBusLeg, previewFinalWalkLeg])
        .padding()
}

#Preview("Leg Row – Walking", traits: .sizeThatFitsLayout) {
    RouteLegRow(leg: previewWalkLeg)
        .padding()
}

#Preview("Leg Row – Transit (Live + Platform)", traits: .sizeThatFitsLayout) {
    RouteLegRow(leg: previewTramLeg)
        .padding()
}

#Preview("Leg Row – Transit (Transfer Warning)", traits: .sizeThatFitsLayout) {
    RouteLegRow(leg: previewBusLeg)
        .padding()
}

#endif
