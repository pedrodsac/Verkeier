import CoreLocation
import Foundation

/// Pre-computed map geometry for drawing a route on a MapKit map.
///
/// Built from a ``RoutePlan`` so the map layer can render polylines and transfer
/// pins without re-deriving them from the plan's legs.
nonisolated struct RouteMapOverlay: Codable, Hashable, Sendable {
    /// One polyline per drawable segment of the route.
    let segments: [RouteMapSegment]
    /// Pins marking transfer points between legs.
    let transferMarkers: [RouteTransferMarker]
    /// Ordered, source-backed stop occurrences. Legacy payloads have none.
    let stopMarkers: [RouteMapStopMarker]

    init(
        segments: [RouteMapSegment],
        transferMarkers: [RouteTransferMarker] = [],
        stopMarkers: [RouteMapStopMarker] = []
    ) {
        self.segments = segments
        self.transferMarkers = transferMarkers
        self.stopMarkers = stopMarkers
    }

    private enum CodingKeys: String, CodingKey {
        case segments, transferMarkers, stopMarkers
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        segments = try values.decode([RouteMapSegment].self, forKey: .segments)
        transferMarkers = try values.decodeIfPresent([RouteTransferMarker].self, forKey: .transferMarkers) ?? []
        stopMarkers = try values.decodeIfPresent([RouteMapStopMarker].self, forKey: .stopMarkers) ?? []
    }

    /// `true` when no segment has enough coordinates to draw a line.
    var isEmpty: Bool {
        segments.allSatisfy { $0.coordinates.count < 2 }
    }
}

/// A single styled polyline within a ``RouteMapOverlay``.
nonisolated struct RouteMapSegment: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier for the segment.
    let id: String
    /// Mode, used to colour/style the polyline.
    let mode: TransportMode
    /// Line label for transit segments.
    let routeName: String?
    /// Public short line name, never inferred from a descriptive route name.
    let routeShortName: String?
    /// Route identifier for transit segments.
    let routeId: String?
    /// Ordered polyline coordinates.
    let coordinates: [RouteMapCoordinate]

    /// Optional styling keeps existing itinerary overlays and stored values compatible.
    let emphasis: RouteMapEmphasis?
    let isApproximate: Bool?

    init(
        id: String,
        mode: TransportMode,
        routeName: String? = nil,
        routeId: String? = nil,
        coordinates: [RouteMapCoordinate],
        emphasis: RouteMapEmphasis? = nil,
        isApproximate: Bool? = nil,
        routeShortName: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.routeName = routeName
        self.routeShortName = routeShortName
        self.routeId = routeId
        self.coordinates = coordinates
        self.emphasis = emphasis
        self.isApproximate = isApproximate
    }
}

/// A pin placed at a transfer point in a ``RouteMapOverlay``.
nonisolated struct RouteTransferMarker: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier for the marker.
    let id: String
    /// Label shown at the transfer point.
    let title: String
    /// Where to place the pin.
    let coordinate: RouteMapCoordinate
}

/// A plain latitude/longitude pair used in map overlays.
///
/// A `Codable`, `Sendable` coordinate without ``LocationPoint``'s identity or
/// name fields. Convert to a MapKit coordinate with ``coordinate``.
nonisolated struct RouteMapCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Creates a coordinate from a ``LocationPoint``, dropping its identity.
    init(_ point: LocationPoint) {
        latitude = point.latitude
        longitude = point.longitude
    }

    /// The coordinate as a MapKit / CoreLocation value.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated enum RouteMapEmphasis: String, Codable, Hashable, Sendable {
    case context, highlighted
}
