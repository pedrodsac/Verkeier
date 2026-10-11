import MapKit

/// Uses MapKit's vector drawing so fixed screen widths stay smooth during zoom.
/// The casing and foreground are separate overlays; overriding draw would force
/// bitmap tiles that visibly change thickness as MapKit replaces zoom levels.
final class RouteTraceRenderer: MKPolylineRenderer {
    init(polyline: MKPolyline, segment: RouteMapSegment, traits: UITraitCollection, isCasing: Bool = false) {
        // Use the designated initializer to avoid convenience-init redispatch.
        super.init(overlay: polyline)
        let isContext = segment.emphasis == .context
        if isCasing {
            strokeColor = UIColor.systemBackground.resolvedColor(with: traits)
                .withAlphaComponent(isContext ? 0.45 : 0.85)
        } else {
            strokeColor = RouteTraceStyle.color(for: segment.mode).resolvedColor(with: traits)
                .withAlphaComponent(isContext ? 0.55 : 1.0)
        }
        lineWidth = (segment.mode == .walking ? 3 : 5) + (isCasing ? 2 : 0)
        lineCap = .round
        lineJoin = .round
        lineDashPattern = segment.mode == .walking ? [6, 4] : segment.isApproximate == true ? [6, 5] : nil
        shouldRasterize = false
        createPath()
    }
}
