import SwiftUI

/// One station / address in the route timeline. The role drives everything:
/// which time(s) show in the gutter, the marker on the rail, and the detail
/// lines (platform, wait, tight-transfer warning) beneath it.
struct TimelinePlaceRow: View {
    let node: PlaceNode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Anchors the rail marker to the first text line. Scales with Dynamic Type;
    /// offset by the row's top padding so it lines up once the columns are padded.
    @ScaledMetric(relativeTo: .headline) private var firstLineCentre = RouteTimelineLayout.firstLineCentre
    /// Grows the time gutter with Dynamic Type so times never clip. Segment rows
    /// scale an empty gutter the same way, keeping the rail aligned.
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth = RouteTimelineLayout.timeColumnWidth

    var body: some View {
        HStack(alignment: .top, spacing: RouteTimelineLayout.columnSpacing) {
            timeColumn
                .padding(.vertical, RouteTimelineLayout.placeRowPadding)

            TimelineRail(
                above: node.railAbove,
                below: node.railBelow,
                marker: marker,
                junctionFromTop: RouteTimelineLayout.placeRowPadding + firstLineCentre
            )
            .frame(width: RouteTimelineLayout.railColumnWidth)

            contentColumn
                .padding(.vertical, RouteTimelineLayout.placeRowPadding)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Time gutter

    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if node.role == .transfer {
                timeText(node.arrivalTime, font: .subheadline, color: .secondary)
                timeText(node.departureTime, font: .subheadline.weight(.semibold), color: .primary)
                delayBadge
            } else {
                timeText(primaryTime, font: primaryTimeFont, color: primaryTimeColor)
                delayBadge
            }
        }
        .frame(width: timeColumnWidth, alignment: .trailing)
        .contentTransition(.numericText())
        .animation(.respectingReduceMotion(.snappy, reduceMotion), value: primaryTime)
    }

    @ViewBuilder
    private func timeText(_ date: Date?, font: Font, color: Color) -> some View {
        if let date {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var delayBadge: some View {
        if node.showsDelayBadge {
            Text(delayText)
                .font(.footnote.weight(.bold))
                .foregroundStyle(delayColor)
                .monospacedDigit()
        }
    }

    // MARK: - Content

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: RouteTimelineLayout.blockLineSpacing) {
            if node.role == .destination {
                Text("Arrive")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            Text(node.name)
                .font(nameFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = detailText {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let bikeAvailabilityText {
                Text(bikeAvailabilityText)
                    .font(.footnote)
                    .foregroundStyle(bikeAvailabilityColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = node.transferWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String? {
        var parts: [String] = []
        if let platform = node.platform, !platform.isEmpty {
            parts.append("Platform \(platform)")
        }
        if node.role == .transfer, let wait = node.waitMinutes {
            parts.append("\(wait) min to change")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var bikeAvailabilityText: String? {
        guard let station = node.bikeShareStation else { return nil }
        switch node.bikeShareStationRole {
        case .pickup:
            guard let count = station.bikesAvailable else { return nil }
            return "\(count) bikes available"
        case .returnStation:
            guard let count = station.docksAvailable else { return nil }
            return "\(count) spots available for return"
        case nil:
            return nil
        }
    }

    private var bikeAvailabilityColor: Color {
        switch node.bikeShareStationRole {
        case .pickup where node.bikeShareStation?.bikesAvailable == 0,
             .returnStation where node.bikeShareStation?.docksAvailable == 0:
            return .orange
        default:
            return .secondary
        }
    }

    // MARK: - Role styling

    private var marker: TimelineRail.Marker {
        switch node.role {
        case .origin: .ring
        case .board, .transfer, .alight: .dot
        case .destination: .pin
        }
    }

    private var nameFont: Font {
        .headline
    }

    /// Time shown for non-transfer roles: departure when leaving, arrival when landing.
    private var primaryTime: Date? {
        switch node.role {
        case .origin, .board: node.departureTime
        case .alight, .destination: node.arrivalTime
        case .transfer: node.departureTime
        }
    }

    private var primaryTimeFont: Font {
        switch node.role {
        // Destination arrival is emphasised, but stays subheadline so it fits the
        // gutter — its prominence comes from the pin, "Arrive" eyebrow, and name.
        case .destination: .subheadline.weight(.bold)
        case .origin: .subheadline
        default: .subheadline.weight(.semibold)
        }
    }

    private var primaryTimeColor: Color {
        node.role == .origin ? .secondary : .primary
    }

    private var delayText: String {
        if node.liveStatus == .cancelled { return "Cancelled" }
        let mins = node.delayMinutes ?? 0
        return mins > 0 ? "+\(mins)" : "\(mins)"
    }

    private var delayColor: Color {
        switch node.liveStatus {
        case .live: .green
        case .delayed: .orange
        case .cancelled: .red
        case .scheduled, .unknown: .secondary
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let arrive = timeSpoken(node.arrivalTime)
        let depart = timeSpoken(node.departureTime)
        switch node.role {
        case .origin:
            return "Leave \(node.name)\(depart.map { " at \($0)" } ?? "")."
        case .board:
            var s = "Board at \(node.name)"
            if let platform = node.platform, !platform.isEmpty { s += ", platform \(platform)" }
            if let depart { s += ", departs \(depart)" }
            if let bikeAvailabilityText { s += ". \(bikeAvailabilityText)" }
            s += "."
            if node.showsDelayBadge { s += " \(delaySpoken)." }
            if let warning = node.transferWarning { s += " Warning: \(warning)." }
            return s
        case .transfer:
            var s = "Transfer at \(node.name)."
            if let arrive { s += " Arrives \(arrive)" }
            if let depart { s += arrive == nil ? " Departs \(depart)" : ", departs \(depart)" }
            if let platform = node.platform, !platform.isEmpty { s += " from platform \(platform)" }
            s += "."
            if node.showsDelayBadge { s += " \(delaySpoken)." }
            if let wait = node.waitMinutes { s += " Wait \(wait) minutes." }
            if let warning = node.transferWarning { s += " Warning: \(warning)." }
            return s
        case .alight:
            var s = "Get off at \(node.name)\(arrive.map { ", arrives \($0)" } ?? "")."
            if let bikeAvailabilityText { s += " \(bikeAvailabilityText)." }
            return s
        case .destination:
            var s = "Arrive at \(node.name)\(arrive.map { " at \($0)" } ?? "")."
            if let bikeAvailabilityText { s += " \(bikeAvailabilityText)." }
            return s
        }
    }

    private func timeSpoken(_ date: Date?) -> String? {
        date?.formatted(date: .omitted, time: .shortened)
    }

    private var delaySpoken: String {
        if node.liveStatus == .cancelled { return "Cancelled" }
        let mins = node.delayMinutes ?? 0
        return mins > 0 ? "delayed \(mins) minutes" : "on time"
    }
}
