import CoreLocation
import Foundation

/// Display helpers for the route screens.
extension RoutePlannerModel {
    var hasDestination: Bool {
        routeDestination != nil
    }

    var originTitle: String {
        routeOrigin?.displayTitle ?? "Current Location"
    }

    var destinationTitle: String {
        routeDestination?.displayTitle ?? "Choose Destination"
    }

    func selectedPlace(for endpoint: RouteEndpoint) -> RoutePlace? {
        switch endpoint {
        case .origin: routeOrigin
        case .destination: routeDestination
        }
    }

    /// Recent places, without the ones already offered above them.
    func recentPlaces(excludingPinnedFor endpoint: RouteEndpoint, currentLocation: RoutePlace?) -> [RoutePlace] {
        let pinnedIDs = Set([currentLocation?.id, selectedPlace(for: endpoint)?.id].compactMap { $0 })
        return recentRoutePlaces.filter { !pinnedIDs.contains($0.id) }
    }

    /// Primary options by departure, or by arrival for "arrive by" searches.
    var chronologicallyOrderedRouteOptions: [RouteOption] {
        routeOptions.sorted { lhs, rhs in
            if case .arriveBy = routePlanningTime {
                let a = lhs.arrivalTime ?? .distantFuture
                let b = rhs.arrivalTime ?? .distantFuture
                if a != b { return a < b }
            }
            let lhsDeparture = lhs.departureTime ?? .distantFuture
            let rhsDeparture = rhs.departureTime ?? .distantFuture
            if lhsDeparture != rhsDeparture { return lhsDeparture < rhsDeparture }
            let lhsArrival = lhs.arrivalTime ?? .distantFuture
            let rhsArrival = rhs.arrivalTime ?? .distantFuture
            if lhsArrival != rhsArrival { return lhsArrival < rhsArrival }
            return lhs.id < rhs.id
        }
    }
}

extension LocationService {
    /// The rider's position as a route endpoint, once a fix is available.
    var currentRoutePlace: RoutePlace? {
        currentLocation.map { location in
            RoutePlace.currentLocation(
                LocationPoint(
                    name: "Current Location",
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )
        }
    }
}
