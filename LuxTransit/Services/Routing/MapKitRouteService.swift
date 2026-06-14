import MapKit

struct MapKitRouteService: RouteService {
    func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation {
        let request = MKDirections.Request()
        request.source = mapItem(for: from)
        request.destination = mapItem(for: to)
        request.transportType = [.transit, .walking]
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw RoutingError.noRouteFound
        }

        let plan = RoutePlan(
            id: "\(from.id)-\(to.id)",
            origin: from,
            destination: to,
            expectedTravelTime: route.expectedTravelTime,
            distanceMeters: route.distance,
            legs: [
                RoutePlan.Leg(
                    id: "mapkit-primary",
                    mode: .unknown,
                    routeName: route.name.isEmpty ? nil : route.name,
                    origin: from,
                    destination: to,
                    departureTime: nil,
                    arrivalTime: nil,
                    distanceMeters: route.distance
                )
            ],
            dataSource: .mapKit
        )

        return RouteCalculation(plan: plan, mapRoute: route)
    }

    func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        let source = mapItem(for: from)
        let destination = mapItem(for: to)

        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
            ]
        )
    }

    private func mapItem(for point: LocationPoint) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: point.latitude, longitude: point.longitude),
            address: nil
        )
        item.name = point.name
        return item
    }
}

enum RoutingError: Error {
    case noRouteFound
}
