import CoreLocation
import Foundation
import HeapModule
import MapKit

struct PublicTransportRouteService: RouteService {
    private let engine: PublicTransportRoutingEngine

    /// - Parameter offlineMode: When true, planning ignores live ATP data (no
    ///   delays/cancellations) and enforces a 15-minute minimum transfer buffer as
    ///   a safety margin. See the routing engine for where the buffer is applied.
    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        roadRouteProvider: any RoadRouteProviding = MapKitRoadRouteProvider(),
        offlineMode: Bool = false,
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
            return calendar
        }()
    ) {
        engine = PublicTransportRoutingEngine(
            gtfsService: gtfsService,
            atpClient: atpClient,
            roadRouteProvider: roadRouteProvider,
            offlineMode: offlineMode,
            now: now,
            calendar: calendar
        )
    }

    nonisolated func calculateRoute(
        from: LocationPoint, to: LocationPoint, time: RoutePlanningTime, filters: RoutePlannerFilters
    ) async throws -> RouteCalculation {
        try await engine.calculateRoute(from: from, to: to, time: time, filters: filters)
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

protocol RoadRouteProviding: Sendable {
    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport: RoadRouteTransport
    ) async -> [RouteMapCoordinate]?
}
