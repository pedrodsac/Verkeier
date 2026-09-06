import CoreLocation
import Foundation
import MapKit

struct PublicTransportRouteService: RouteService {
    private let calculationCoordinator: RouteCalculationCoordinator

    /// - Parameter offlineMode: When true, planning ignores live ATP data (no
    ///   delays/cancellations) and enforces a 15-minute minimum transfer buffer as
    ///   a safety margin. See the routing engine for where the buffer is applied.
    init(
        gtfsService: any GTFSService,
        atpClient: any ATPClient,
        bikeShareService: any BikeShareService = UnavailableBikeShareService(),
        roadRouteProvider: any RoadRouteProviding = MapKitRoadRouteProvider(),
        offlineMode: Bool = false,
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
            return calendar
        }(),
        concurrency: RouteCalculationConcurrency = .default,
        realtimeBoardBudgetSeconds: TimeInterval = 8,
        roadGeometryBudgetSeconds: TimeInterval = 1
    ) {
        let engine = PublicTransportRoutingEngine(
            gtfsService: gtfsService,
            atpClient: atpClient,
            bikeShareService: bikeShareService,
            roadRouteProvider: roadRouteProvider,
            offlineMode: offlineMode,
            now: now,
            calendar: calendar,
            concurrency: concurrency,
            realtimeBoardBudgetSeconds: realtimeBoardBudgetSeconds,
            roadGeometryBudgetSeconds: roadGeometryBudgetSeconds
        )
        calculationCoordinator = RouteCalculationCoordinator(engine: engine)
    }

    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        try await calculationCoordinator.calculate(
            from: from,
            to: to,
            time: time,
            filters: filters,
            realtimeRefreshPolicy: realtimeRefreshPolicy,
            page: page
        )
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

/// Serializes route requests at the service boundary while still allowing each
/// calculation to fan out internally. Starting a new request cancels the old
/// task, which prevents stale work from consuming realtime or MapKit capacity.
private actor RouteCalculationCoordinator {
    private let engine: PublicTransportRoutingEngine
    private var activeTask: Task<RouteCalculation, Error>?
    private var generation = 0

    init(engine: PublicTransportRoutingEngine) {
        self.engine = engine
    }

    func calculate(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        activeTask?.cancel()
        generation += 1
        let requestGeneration = generation

        let task = Task { @concurrent in
            try await engine.calculateRoute(
                from: from,
                to: to,
                time: time,
                filters: filters,
                forceRealtimeRefresh: realtimeRefreshPolicy == .forceRefresh,
                page: page
            )
        }
        activeTask = task
        defer {
            if requestGeneration == generation {
                activeTask = nil
            }
        }
        let result = try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
        try Task.checkCancellation()
        guard requestGeneration == generation else {
            throw CancellationError()
        }
        return result
    }
}

protocol RoadRouteProviding: Sendable {
    /// Returns the traveled route distance and its map geometry.
    ///
    /// The default implementation keeps existing lightweight providers useful:
    /// providers that only return coordinates get their distance measured along
    /// that polyline.
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

        let distanceMeters = polylineDistanceMeters(coordinates)
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        return RoadRoute(coordinates: coordinates, distanceMeters: distanceMeters)
    }
}

private nonisolated func polylineDistanceMeters(_ coordinates: [RouteMapCoordinate]) -> Double {
    zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
        total + routeSearchDistanceMeters(
            from: LocationPoint(latitude: pair.0.latitude, longitude: pair.0.longitude),
            to: LocationPoint(latitude: pair.1.latitude, longitude: pair.1.longitude)
        )
    }
}
