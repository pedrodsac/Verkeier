import MapKit

struct MapKitRouteService: RouteService {
    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        // This adapter provides an unavailable default and explicit Apple Maps
        // handoff. All in-app journey calculations use MobiliteitKit.
        throw RoutingError.timetableUnavailable
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        let source = mapItem(for: from)
        let destination = mapItem(for: to)

        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
            ]
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
