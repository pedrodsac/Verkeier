import CoreLocation
import MapKit

final class StopMapAnnotation: NSObject, MKAnnotation {
    enum Layer {
        case liveNearby
        case gtfs
    }

    private(set) var stop: Stop
    let layer: Layer

    var key: String {
        "\(layer)-\(stop.id)"
    }

    @objc dynamic var coordinate: CLLocationCoordinate2D {
        stop.location.coordinate
    }

    @objc dynamic var title: String? {
        stop.displayName
    }

    init(stop: Stop, layer: Layer) {
        self.stop = stop
        self.layer = layer
    }

    func update(stop: Stop) {
        guard self.stop != stop else { return }
        willChangeValue(forKey: "coordinate")
        willChangeValue(forKey: "title")
        self.stop = stop
        didChangeValue(forKey: "title")
        didChangeValue(forKey: "coordinate")
    }
}

final class BikeShareMapAnnotation: NSObject, MKAnnotation {
    private(set) var station: BikeShareStation

    var key: String { "bike-share-\(station.id)" }
    @objc dynamic var coordinate: CLLocationCoordinate2D { station.location.coordinate }
    @objc dynamic var title: String? { station.displayName }
    @objc dynamic var subtitle: String? {
        let bikes = station.bikesAvailable.map { "\($0) bikes" } ?? "bikes unknown"
        let docks = station.docksAvailable.map { "\($0) free docks" } ?? "docks unknown"
        return "\(bikes) · \(docks)"
    }

    nonisolated init(station: BikeShareStation) {
        self.station = station
    }

    func update(station: BikeShareStation) {
        guard self.station != station else { return }
        willChangeValue(forKey: "coordinate")
        willChangeValue(forKey: "title")
        willChangeValue(forKey: "subtitle")
        self.station = station
        didChangeValue(forKey: "subtitle")
        didChangeValue(forKey: "title")
        didChangeValue(forKey: "coordinate")
    }
}
