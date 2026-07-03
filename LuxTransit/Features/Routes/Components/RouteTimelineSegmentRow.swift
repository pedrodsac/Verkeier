import SwiftUI

/// The movement between two places: a ride (line badge + "toward …" direction +
/// duration) or a walk/transfer (a single detail line, with the walking glyph
/// carried on the rail rather than beside the text).
struct TimelineSegmentRow: View {
    let node: SegmentNode
    var alerts: [AlertMessage] = []

    /// Matches ``TimelinePlaceRow``'s gutter (same base + trait) so the rail stays
    /// aligned as Dynamic Type scales.
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth = RouteTimelineLayout.timeColumnWidth

    var body: some View {
        HStack(alignment: .center, spacing: RouteTimelineLayout.columnSpacing) {
            // Empty gutter keeps the rail aligned with the place rows above/below.
            Color.clear
                .frame(width: timeColumnWidth)

            TimelineRail(
                above: node.rail,
                below: node.rail,
                marker: node.kind == .transit ? .none : .walk
            )
            .frame(width: RouteTimelineLayout.railColumnWidth)

            content
                .padding(.vertical, RouteTimelineLayout.segmentRowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .transit:
            VStack(alignment: .leading, spacing: RouteTimelineLayout.blockLineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TimelineLineBadge(text: node.badgeText ?? node.mode.displayName, mode: node.mode)
                    if let headsign = node.headsign, !headsign.isEmpty {
                        Text("toward \(headsign)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let mins = node.durationMinutes {
                    Text("Ride \(mins) min")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !alerts.isEmpty {
                    Label("Disruption", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Disruption affects this leg")
                }
            }
        case .walk, .transfer:
            Text(walkText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var walkText: String {
        let mins = node.durationMinutes
        if node.kind == .transfer {
            return mins.map { "Transfer \($0) min" } ?? "Transfer"
        }
        let dist = node.distanceMeters.map(distanceText)
        switch (mins, dist) {
        case let (.some(m), .some(d)): return "Walk \(m) min · \(d)"
        case let (.some(m), .none): return "Walk \(m) min"
        case let (.none, .some(d)): return "Walk \(d)"
        case (.none, .none): return "Walk"
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
    }

    private var accessibilityLabel: String {
        switch node.kind {
        case .transit:
            var s = "Ride \(node.mode.displayName)"
            if let badge = node.badgeText { s += " \(badge)" }
            if let headsign = node.headsign, !headsign.isEmpty { s += " toward \(headsign)" }
            if let mins = node.durationMinutes { s += ", \(mins) minutes" }
            s += "."
            if !alerts.isEmpty { s += " Disruption affects this leg." }
            return s
        case .transfer:
            return node.durationMinutes.map { "Transfer on foot, \($0) minutes." } ?? "Transfer on foot."
        case .walk:
            var s = "Walk"
            if let mins = node.durationMinutes { s += " \(mins) minutes" }
            if let dist = node.distanceMeters { s += ", \(distanceText(dist))" }
            s += "."
            return s
        }
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
