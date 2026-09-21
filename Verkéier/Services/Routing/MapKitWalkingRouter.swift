import CoreLocation
import Foundation
import MapKit

/// Network-backed fallback used only when no valid local graph is available.
nonisolated struct MapKitWalkingRouter: WalkingRouting {
    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        try await withThrowingTaskGroup(of: OfflineWalkingEstimate.self, returning: [OfflineWalkingEstimate].self) { group in
            for destination in destinations {
                group.addTask {
                    let route = try await route(from: origin, to: destination.location)
                    return OfflineWalkingEstimate(
                        destinationID: destination.id,
                        distanceMeters: route.distanceMeters,
                        duration: route.duration,
                        source: .mapKit
                    )
                }
            }
            var estimates: [OfflineWalkingEstimate] = []
            for try await estimate in group { estimates.append(estimate) }
            return estimates
        }
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first, route.polyline.pointCount >= 2 else {
            throw WalkingRoutingError.noRoute
        }
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        return OfflineWalkingRoute(
            distanceMeters: route.distance,
            duration: route.expectedTravelTime,
            coordinates: coordinates.map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
            source: .mapKit
        )
    }

    private func mapItem(for point: LocationPoint) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil)
        item.name = point.name
        return item
    }
}

nonisolated struct StraightLineWalkingRouter: WalkingRouting {
    private let walkingSpeedMetersPerSecond = 1.25
    private let pathStretchFactor = 1.2

    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        destinations.map { destination in
            let route = routeValue(from: origin, to: destination.location)
            return OfflineWalkingEstimate(
                destinationID: destination.id,
                distanceMeters: route.distanceMeters,
                duration: route.duration,
                source: .straightLineEstimate
            )
        }
    }

    func route(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        routeValue(from: origin, to: destination)
    }

    private func routeValue(from origin: LocationPoint, to destination: LocationPoint) -> OfflineWalkingRoute {
        let directDistance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        let distanceMeters = directDistance * pathStretchFactor
        return OfflineWalkingRoute(
            distanceMeters: distanceMeters,
            duration: max(1, distanceMeters / walkingSpeedMetersPerSecond),
            coordinates: [
                RouteMapCoordinate(latitude: origin.latitude, longitude: origin.longitude),
                RouteMapCoordinate(latitude: destination.latitude, longitude: destination.longitude),
            ],
            source: .straightLineEstimate
        )
    }
}
