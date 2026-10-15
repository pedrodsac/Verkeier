import SwiftUI

/// The movement between two places: a ride (line badge + destination direction +
/// duration) or a walk/transfer (a single detail line, with the walking glyph
/// carried on the rail rather than beside the text).
struct RouteTimelineSegmentRow: View {
    let node: SegmentNode
    var alerts: [AlertMessage] = []

    /// Matches ``RouteTimelinePlaceRow``'s gutter (same base + trait) so the rail stays
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
            RouteTimelineRail(
                above: node.rail,
                below: node.rail,
                marker: railMarker
            )
            .frame(width: RouteTimelineLayout.railColumnWidth)
            .offset(x: timeColumnWidth + RouteTimelineLayout.columnSpacing)
        }
        .accessibilityElement(children: node.tripSelection == nil ? .combine : .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .transit:
            VStack(alignment: .leading, spacing: RouteTimelineLayout.blockLineSpacing) {
                if let selection = node.tripSelection {
                    NavigationLink(value: SheetRoute.tripDetail(selection)) {
                        transitBadge
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint("Shows every stop and its live status")
                } else {
                    transitBadge
                }
                if node.hasCancelledContinuation {
                    Label("Cancelled", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                }
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
                LineBadge(name: "vel’OH!", mode: .bicycle, size: .compact)
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
        case .funicular:
            Text(node.durationMinutes.map { "Funicular \($0) min" } ?? "Funicular")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .walk, .transfer:
            Text(walkText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transitBadge: some View {
        RideCard(
            routeText: node.badgeText ?? node.mode.displayName,
            mode: node.mode,
            direction: node.headsign
        )
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

    private var railMarker: RouteTimelineRail.Marker {
        switch node.kind {
        case .transit: .none
        case .bikeShare: .bicycle
        case .funicular: .funicular
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
            if let count = node.stopCount { s += ", \(count) stops" }
            s += "."
            for caption in node.continuationCaptions { s += " \(caption). Stay aboard." }
            if node.hasCancelledContinuation { s += " Cancelled." }
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
        case .funicular:
            return node.durationMinutes.map { "Funicular, \($0) minutes." } ?? "Funicular."
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
