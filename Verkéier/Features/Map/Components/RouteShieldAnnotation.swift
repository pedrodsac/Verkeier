import MapKit

final class RouteShieldAnnotation: NSObject, MKAnnotation {
    private(set) var segment: RouteMapSegment
    @objc dynamic private(set) var coordinate: CLLocationCoordinate2D
    var isPlaced = false

    init(segment: RouteMapSegment) {
        self.segment = segment
        coordinate = segment.coordinates.first?.coordinate ?? CLLocationCoordinate2D()
    }

    func update(_ segment: RouteMapSegment) { self.segment = segment }

    func move(to coordinate: CLLocationCoordinate2D) {
        guard self.coordinate.latitude != coordinate.latitude || self.coordinate.longitude != coordinate.longitude else { return }
        self.coordinate = coordinate
    }
}
