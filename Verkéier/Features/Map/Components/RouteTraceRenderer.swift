import MapKit

/// Immutable drawing inputs: MapKit can draw separate tiles concurrently.
final class RouteTraceRenderer: MKPolylineRenderer {
    private let traceColor: CGColor
    private let casingColor: CGColor
    private let traceWidth: CGFloat
    private let dashes: [CGFloat]
    private var tracePath: CGPath?

    init(polyline: MKPolyline, segment: RouteMapSegment, traits: UITraitCollection) {
        let opacity = segment.emphasis == .context ? 0.55 : 1.0
        traceColor = RouteTraceStyle.color(for: segment.mode).resolvedColor(with: traits)
            .withAlphaComponent(opacity).cgColor
        casingColor = UIColor.systemBackground.resolvedColor(with: traits)
            .withAlphaComponent(segment.emphasis == .context ? 0.45 : 0.85).cgColor
        traceWidth = segment.mode == .walking ? 3 : 5
        dashes = segment.mode == .walking ? [6, 4] : segment.isApproximate == true ? [6, 5] : []
        // MKPolylineRenderer's convenience initializer redispatches through
        // self.init(overlay:). Call the designated initializer directly so a
        // subclass with custom drawing inputs does not hit its inherited trap.
        super.init(overlay: polyline)
        createPath()
        // Written once before publishing the renderer, then only read by draw.
        tracePath = path?.copy()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let tracePath, zoomScale > 0 else { return }
        context.saveGState()
        context.clip(to: rect(for: mapRect))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: dashes.map { $0 / zoomScale })
        context.setStrokeColor(casingColor)
        context.setLineWidth((traceWidth + 2) / zoomScale)
        context.addPath(tracePath)
        context.strokePath()
        context.setStrokeColor(traceColor)
        context.setLineWidth(traceWidth / zoomScale)
        context.addPath(tracePath)
        context.strokePath()
        context.restoreGState()
    }
}
