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

            TimelineRail(
                above: node.rail,
                below: node.rail,
                marker: railMarker
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

/// A destination card that is intentionally separate from the line-number
/// card. The overlap makes the number feel anchored to the destination while
/// preserving the original number card's shape.
private struct TimelineTransitBadge: View {
    let routeText: String
    let mode: TransportMode
    let direction: String?

    var body: some View {
        HStack(alignment: .center, spacing: -8) {
            TimelineLineBadge(text: routeText, mode: mode)
                .zIndex(1)

            if let direction, !direction.isEmpty {
                TimelineDestinationCard(text: direction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Measures the direction against the actual space left beside the line card.
/// This avoids relying on ``ViewThatFits``' proposal, which can be wider than
/// the destination's final space inside the timeline HStack.
private struct TimelineDestinationCard: View {
    let text: String

    @State private var textWidth: CGFloat = 0

    private let leadingInset: CGFloat = 18
    private let trailingInset: CGFloat = 12
    private let destinationFont = Font.subheadline.weight(.semibold)

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let intrinsicWidth = textWidth + leadingInset + trailingInset
            let isOverflowing = textWidth > 0 && intrinsicWidth > availableWidth + 1
            let cardWidth = isOverflowing ? availableWidth : min(intrinsicWidth, availableWidth)

            ZStack(alignment: .leading) {
                if isOverflowing {
                    OverflowMarqueeText(
                        text: text,
                        font: destinationFont,
                        initialLeadingInset: leadingInset,
                        forceScroll: true
                    )
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.trailing, trailingInset)
                } else {
                    Text(text)
                        .font(destinationFont)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, leadingInset)
                        .padding(.trailing, trailingInset)
                }
            }
            .foregroundStyle(.primary)
            .frame(width: cardWidth, alignment: .leading)
            .frame(minHeight: 28, alignment: .center)
            .background(destinationBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Text(text)
                .font(destinationFont)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: TimelineDestinationTextWidthKey.self, value: proxy.size.width)
                    }
                }
                .hidden()
                .allowsHitTesting(false)
        }
        .onPreferenceChange(TimelineDestinationTextWidthKey.self) { width in
            guard abs(textWidth - width) > 0.5 else { return }
            textWidth = width
        }
    }

    private var destinationBackground: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.92),
                .gray.opacity(0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct TimelineDestinationTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
