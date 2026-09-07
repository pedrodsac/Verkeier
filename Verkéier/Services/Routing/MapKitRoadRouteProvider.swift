import CoreLocation
import Foundation
import MapKit

func routeSearchDistanceMeters(from origin: LocationPoint, to destination: LocationPoint) -> Double {
    CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
}

protocol RoadRouteProviding: Sendable {
    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> RoadRoute?

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]?
}

extension RoadRouteProviding {
    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> RoadRoute? {
        guard let coordinates = await roadRouteCoordinates(
            from: origin,
            to: destination,
            transport: transport
        ), coordinates.count >= 2 else {
            return nil
        }

        let distanceMeters = zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(
                latitude: pair.0.latitude,
                longitude: pair.0.longitude
            ).distance(from: CLLocation(
                latitude: pair.1.latitude,
                longitude: pair.1.longitude
            ))
        }
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        return RoadRoute(coordinates: coordinates, distanceMeters: distanceMeters)
    }
}

enum RoadRouteTransport: String, Sendable {
    case automobile
    case walking
    case bicycle
}

/// A route returned by a road-routing provider.
///
/// `distanceMeters` is the distance traveled along the route, rather than the
/// straight-line distance between its endpoints. Keeping it alongside the
/// polyline prevents callers from having to infer travel distance from map
/// presentation data.
struct RoadRoute: Sendable {
    let coordinates: [RouteMapCoordinate]
    let distanceMeters: Double
}

struct MapKitRoadRouteProvider: RoadRouteProviding {
    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        await roadRoute(from: origin, to: destination, transport: transport)?.coordinates
    }

    nonisolated func roadRoute(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> RoadRoute? {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = transport.mapKitTransportType
        request.requestsAlternateRoutes = false

        guard let route = try? await MKDirections(request: request).calculate().routes.first,
              route.polyline.pointCount >= 2 else {
            return nil
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: route.polyline.pointCount)
        )

        return RoadRoute(
            coordinates: coordinates.map {
                RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            distanceMeters: route.distance
        )
    }

    private nonisolated func mapItem(for point: LocationPoint) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: point.latitude, longitude: point.longitude),
            address: nil
        )
        item.name = point.name
        return item
    }
}

extension RoadRouteTransport {
    nonisolated init?(_ hint: RouteLegRoadRoutingHint) {
        switch hint {
        case .none:
            return nil
        case .automobile:
            self = .automobile
        case .walking:
            self = .walking
        case .bicycle:
            self = .bicycle
        }
    }

    nonisolated var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .walking: .walking
        case .bicycle: .walking
        }
    }
}
