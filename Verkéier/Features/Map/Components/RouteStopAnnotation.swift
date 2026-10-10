import MapKit

final class RouteStopAnnotation: NSObject, MKAnnotation {
    private(set) var marker: RouteMapStopMarker
    var placement: RouteTraceLayout.StopPlacement?

    @objc dynamic var coordinate: CLLocationCoordinate2D { marker.coordinate.coordinate }
    @objc dynamic var title: String? { marker.name }

    init(marker: RouteMapStopMarker) { self.marker = marker }

    func update(_ marker: RouteMapStopMarker) {
        guard self.marker != marker else { return }
        let moves = self.marker.coordinate != marker.coordinate
        let renames = self.marker.name != marker.name
        if moves { willChangeValue(forKey: "coordinate") }
        if renames { willChangeValue(forKey: "title") }
        self.marker = marker
        if renames { didChangeValue(forKey: "title") }
        if moves { didChangeValue(forKey: "coordinate") }
    }
}
