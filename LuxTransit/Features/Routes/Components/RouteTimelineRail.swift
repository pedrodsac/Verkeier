import SwiftUI

/// Draws one row's slice of the connecting rail: an upper half (`above`) and a
/// lower half (`below`), each solid or dotted per ``RailStyle``, plus a marker
/// centred on the junction. With `VStack(spacing: 0)` the per-row slices join
/// into one continuous rail.
struct TimelineRail: View {
    let above: RailStyle?
    let below: RailStyle?
    let marker: Marker
    /// Where the marker and the above/below rail meet, measured from the top.
    /// `nil` centres it — used by segment rows, where the rail passes through.
    var junctionFromTop: CGFloat?

    /// What sits on the junction. Places pick by role; segments pass through or
    /// interrupt the walk rail with a glyph.
    enum Marker: Equatable {
        /// Segment pass-through — no marker.
        case none
        /// Journey origin — a hollow ring.
        case ring
        /// Board / transfer / alight — a filled dot in the adjacent rail's tint.
        case dot
        /// Journey destination — a red map pin.
        case pin
        /// A walk / transfer segment — the walking glyph on a material disc.
        case walk
    }

    @ScaledMetric(relativeTo: .headline) private var dotSize = RouteTimelineLayout.dotSize
    @ScaledMetric(relativeTo: .headline) private var ringSize = RouteTimelineLayout.ringSize
    @ScaledMetric(relativeTo: .headline) private var pinSize = RouteTimelineLayout.pinSize
    @ScaledMetric(relativeTo: .subheadline) private var walkSize = RouteTimelineLayout.walkDiscSize

    var body: some View {
        GeometryReader { proxy in
            let midX = proxy.size.width / 2
            let junctionY = junctionFromTop ?? proxy.size.height / 2
            ZStack {
                if let above {
                    railLine(above, from: CGPoint(x: midX, y: 0), to: CGPoint(x: midX, y: junctionY))
                }
                if let below {
                    railLine(below, from: CGPoint(x: midX, y: junctionY), to: CGPoint(x: midX, y: proxy.size.height))
                }
                markerView
                    .position(x: midX, y: junctionY)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .none:
            EmptyView()
        case .ring:
            Circle()
                .strokeBorder(.tertiary, lineWidth: RouteTimelineLayout.railWidth)
                .frame(width: ringSize, height: ringSize)
        case .dot:
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
        case .pin:
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: pinSize))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        case .walk:
            Image(systemName: "figure.walk")
                .font(.system(size: walkSize * 0.6, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: walkSize, height: walkSize)
                .background(.regularMaterial, in: Circle())
        }
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

// MARK: - Layout constants

enum RouteTimelineLayout {
    static let timeColumnWidth: CGFloat = 46
    static let railColumnWidth: CGFloat = 16
    static let columnSpacing: CGFloat = 12
    static let railWidth: CGFloat = 2.5
    static let dotSize: CGFloat = 8
    static let ringSize: CGFloat = 12
    static let pinSize: CGFloat = 20
    static let walkDiscSize: CGFloat = 22
    /// Vertical padding inside a place row's columns — kept in sync with the
    /// marker's junction offset so the marker anchors to the first text line.
    static let placeRowPadding: CGFloat = 8
    static let segmentRowPadding: CGFloat = 12
    static let blockLineSpacing: CGFloat = 3
    /// Centre of the first text line from the top of the (unpadded) content,
    /// scaled to the place name's font, so the marker sits on the first line.
    static let firstLineCentre: CGFloat = 11
}
