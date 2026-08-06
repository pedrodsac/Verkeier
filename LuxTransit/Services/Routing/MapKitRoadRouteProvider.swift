import CoreLocation
import Foundation
import MapKit

enum RoadRouteTransport: String {
    case automobile
    case walking
    case bicycle
}

struct MapKitRoadRouteProvider: RoadRouteProviding {
    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
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

        return coordinates.map {
            RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
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
