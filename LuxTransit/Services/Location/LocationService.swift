import CoreLocation
import Observation

/// Observable wrapper around `CLLocationManager` for when-in-use location.
///
/// Main-actor isolated and `@Observable` so SwiftUI views can read
/// ``authorizationStatus`` and ``currentLocation`` directly. Delegate callbacks
/// arrive off the main actor and are hopped back on before mutating state.
@Observable
@MainActor
final class LocationService: NSObject {
    /// Current Core Location authorization status.
    var authorizationStatus: CLAuthorizationStatus
    /// Most recent location fix, or `nil` until one is delivered.
    var currentLocation: CLLocation?

    @ObservationIgnored private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Requests when-in-use authorization, or starts updates immediately if
    /// access has already been decided.
    func requestWhenInUseAuthorization() {
        guard authorizationStatus == .notDetermined else {
            startUpdatingIfAllowed()
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    /// Begins location updates when authorization permits; otherwise a no-op.
    func startUpdatingIfAllowed() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return
        }
        manager.startUpdatingLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            startUpdatingIfAllowed()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failures are surfaced in later phases when nearby stops use live location.
    }
}
