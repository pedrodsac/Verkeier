import SwiftUI

/// The movement between two places: a ride (line badge + destination direction +
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

            Color.clear
            .frame(width: RouteTimelineLayout.railColumnWidth)

            content
                .padding(.vertical, RouteTimelineLayout.segmentRowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .leading) {
            TimelineRail(
                above: node.rail,
                below: node.rail,
                marker: railMarker
            )
            .frame(width: RouteTimelineLayout.railColumnWidth)
            .offset(x: timeColumnWidth + RouteTimelineLayout.columnSpacing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .transit:
            VStack(alignment: .leading, spacing: RouteTimelineLayout.blockLineSpacing) {
                TimelineTransitBadge(
                    routeText: node.badgeText ?? node.mode.displayName,
                    mode: node.mode,
                    direction: node.headsign
                )
                if let mins = node.durationMinutes {
                    Text(durationText(minutes: mins, stopCount: node.stopCount))
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
        case .bikeShare:
            VStack(alignment: .leading, spacing: RouteTimelineLayout.blockLineSpacing) {
                TimelineLineBadge(text: "vel’OH!", mode: .bicycle)
                if let mins = node.durationMinutes {
                    let distance = node.distanceMeters.map(distanceText) ?? "estimated"
                    Text("\(mins) min · \(distance)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if node.bikeShareDetails?.isAvailabilityWarning == true {
                    Label("Availability may have changed", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
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

    private func durationText(minutes: Int, stopCount: Int?) -> String {
        guard let stopCount else { return "\(minutes) min" }
        let stopLabel = stopCount == 1 ? "stop" : "stops"
        return "\(minutes) min · \(stopCount) \(stopLabel)"
    }

    private var railMarker: TimelineRail.Marker {
        switch node.kind {
        case .transit: .none
        case .bikeShare: .bicycle
        case .walk, .transfer: .walk
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
            if let headsign = node.headsign, !headsign.isEmpty { s += " to \(headsign)" }
            if let mins = node.durationMinutes { s += ", \(mins) minutes" }
            s += "."
            if !alerts.isEmpty { s += " Disruption affects this leg." }
            return s
        case .bikeShare:
            var s = "Ride a vel’OH! bike"
            if let mins = node.durationMinutes { s += ", \(mins) minutes" }
            if let details = node.bikeShareDetails {
                if let bikes = details.pickupStation.bikesAvailable {
                    s += ". \(bikes) bikes available at \(details.pickupStation.displayName)."
                }
                if let docks = details.returnStation.docksAvailable {
                    s += " \(docks) spots available for return at \(details.returnStation.displayName)."
                }
            }
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

/// The original line-number card, kept independent so it can sit above the
/// destination card without changing its sizing, font, or corner radius.
private struct TimelineLineBadge: View {
    let text: String
    let mode: TransportMode

    private let horizontalInset: CGFloat = 6
    private let verticalInset: CGFloat = 2

    var body: some View {
        Text(text)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, verticalInset)
            .background(
                mode.tint.gradient,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

/// One compact card containing the line badge and its destination.
private struct TimelineTransitBadge: View {
    let routeText: String
    let mode: TransportMode
    let direction: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            card {
                destinationText
                    .fixedSize(horizontal: true, vertical: false)
            }

            card {
                if let direction, !direction.isEmpty {
                    OverflowMarqueeText(
                        text: direction,
                        font: .subheadline.weight(.semibold),
                        initialLeadingInset: 0,
                        forceScroll: true,
                        foregroundColor: .black
                    )
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationText: some View {
        Text(direction ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }

    private func card<Destination: View>(
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            TimelineLineBadge(text: routeText, mode: mode)
            destination()
        }
        .foregroundStyle(.black)
        .padding(3)
        .padding(.trailing, 5)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 0.75, x: 0, y: 0)
    }
}
