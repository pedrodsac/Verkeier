import MapKit

/// Immutable drawing inputs: MapKit can draw separate tiles concurrently.
final class RouteTraceRenderer: MKPolylineRenderer {
    private let traceColor: CGColor
    private let casingColor: CGColor
    private let traceWidth: CGFloat
    private let casingWidth: CGFloat
    private let dashes: [CGFloat]
    private var tracePath: CGPath?

    init(polyline: MKPolyline, segment: RouteMapSegment, traits: UITraitCollection) {
        let isFaded = segment.emphasis == .context || segment.isApproximate == true
        let opacity = isFaded ? 0.55 : 1.0
        traceColor = RouteTraceStyle.color(for: segment.mode).resolvedColor(with: traits)
            .withAlphaComponent(opacity).cgColor
        casingColor = UIColor.systemBackground.resolvedColor(with: traits)
            .withAlphaComponent(isFaded ? 0.45 : 1.0).cgColor
        // Geographic widths shrink on screen as the map zooms out. Convert
        // metres to MapKit's drawing units once, without zoom compensation.
        let pointsPerMetre = CGFloat(MKMapPointsPerMeterAtLatitude(polyline.coordinate.latitude))
        traceWidth = (segment.mode == .walking ? 3 : 5) * pointsPerMetre
        casingWidth = traceWidth + 2 * pointsPerMetre
        let dashMetres: [CGFloat] = segment.mode == .walking ? [6, 4] : segment.isApproximate == true ? [6, 5] : []
        dashes = dashMetres.map { $0 * pointsPerMetre }
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
        context.setLineDash(phase: 0, lengths: dashes)
        context.setStrokeColor(casingColor)
        context.setLineWidth(casingWidth)
        context.addPath(tracePath)
        context.strokePath()
        context.setStrokeColor(traceColor)
        context.setLineWidth(traceWidth)
        context.addPath(tracePath)
        context.strokePath()
        context.restoreGState()
    }
}
