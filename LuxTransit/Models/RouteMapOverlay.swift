import CoreLocation
import Foundation

nonisolated struct RouteMapOverlay: Codable, Hashable, Sendable {
    let segments: [RouteMapSegment]
    let transferMarkers: [RouteTransferMarker]

    init(
        segments: [RouteMapSegment],
        transferMarkers: [RouteTransferMarker] = []
    ) {
        self.segments = segments
        self.transferMarkers = transferMarkers
    }

    var isEmpty: Bool {
        segments.allSatisfy { $0.coordinates.count < 2 }
    }
}

nonisolated struct RouteMapSegment: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let mode: TransportMode
    let routeName: String?
    let routeId: String?
    let coordinates: [RouteMapCoordinate]

    init(
        id: String,
        mode: TransportMode,
        routeName: String? = nil,
        routeId: String? = nil,
        coordinates: [RouteMapCoordinate]
    ) {
        self.id = id
        self.mode = mode
        self.routeName = routeName
        self.routeId = routeId
        self.coordinates = coordinates
    }
}

nonisolated struct RouteTransferMarker: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let coordinate: RouteMapCoordinate
}

nonisolated struct RouteMapCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ point: LocationPoint) {
        latitude = point.latitude
        longitude = point.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
