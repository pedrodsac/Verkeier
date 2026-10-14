import CoreLocation
import MapKit
import SwiftUI

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

struct LocationPermissionButton: View {
    let authorizationStatus: CLAuthorizationStatus
    let requestLocation: () -> Void

    var body: some View {
        Button(action: requestLocation) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "location.fill"
        case .denied, .restricted:
            "location.slash.fill"
        case .notDetermined:
            "location"
        @unknown default:
            "location"
        }
    }

    private var accessibilityLabel: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Center on current location"
        case .denied, .restricted:
            "Location access unavailable"
        case .notDetermined:
            "Allow current location"
        @unknown default:
            "Current location"
        }
    }
}
