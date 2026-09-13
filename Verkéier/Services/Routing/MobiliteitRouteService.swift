import Foundation
import MapKit
import MobiliteitKit

/// App adapter for MobiliteitKit's on-device GTFS/RAPTOR journey engine.
/// It deliberately maps into the existing RoutePlan surface so route sheets,
/// map overlays, accessibility, and paging UI need no parallel presentation
/// model.
struct MobiliteitRouteService: RouteService {
    let databaseURL: URL
    private let gtfsService: (any GTFSService)?
    private let fallback = MapKitRouteService()

    init(
        databaseURL: URL = MobiliteitGTFSService.installedDatabaseURL,
        gtfsService: (any GTFSService)? = nil
    ) {
        self.databaseURL = databaseURL
        self.gtfsService = gtfsService
    }

    nonisolated func calculateRoute(
        from: LocationPoint,
        to: LocationPoint,
        time: RoutePlanningTime,
        filters: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page: RouteSearchPage
    ) async throws -> RouteCalculation {
        // A route request may arrive while the launch-time GTFS refresh is
        // still running. Await that same refresh here rather than allowing an
        // expired or half-installed timetable to degrade into a walking-only
        // route.
        if let gtfsService {
            let status = await gtfsService.refreshIfNeeded(force: false)
            guard status.isReady else { throw RoutingError.timetableUnavailable }
        }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw RoutingError.timetableUnavailable
        }
        let anchor: Date = switch time {
        case .leaveNow: .now
        case let .departAt(value): value
        // The on-device engine is leave-after. For arrive-by the app starts an
        // earlier profile window; users can refine with Earlier from there.
        case let .arriveBy(value): value.addingTimeInterval(-2 * 60 * 60)
        }
        let searchAnchor: Date = switch page {
        case .initial: anchor
        case let .later(boundary, _): boundary.addingTimeInterval(1)
        case let .earlier(boundary, _): boundary.addingTimeInterval(-2 * 60 * 60)
        }
        do {
            let router = try await TransitRouter(databaseURL: databaseURL, walkingProvider: MapKitWalkingProvider())
            let session = try await router.makeSession(for: RouteQuery(
                origin: endpoint(from), destination: endpoint(to), departureTime: searchAnchor,
                preferences: preferences(filters)
            ))
            let journeyPage = try await session.initial(count: max(page.resultLimit, 5))
            var journeys = journeyPage.journeys
            if case let .earlier(boundary, limit) = page {
                journeys = journeys.filter { $0.effectiveDeparture < boundary }
                journeys = Array(journeys.suffix(limit))
            } else if case let .later(boundary, limit) = page {
                journeys = Array(journeys.filter { $0.effectiveDeparture > boundary }.prefix(limit))
            }
            let options = journeys.map { option(from: $0, origin: from, destination: to) }
            guard !options.isEmpty else { throw RoutingError.noPublicTransportRoute }
            return RouteCalculation(options: options, selectedOptionID: options.first?.id)
        } catch let error as RoutingError { throw error
        } catch { throw RoutingError.noRouteFound }
    }

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {
        fallback.openInAppleMaps(from: from, to: to)
    }

    private nonisolated func endpoint(_ point: LocationPoint) -> JourneyEndpoint {
        // GTFS stop IDs are preserved as LocationPoint IDs by the app's stop
        // mapping. Coordinates remain valid for search/current-location input.
        .coordinate(Coordinate(latitude: point.latitude, longitude: point.longitude), label: point.name)
    }

    private nonisolated func preferences(_ filters: RoutePlannerFilters) -> RoutingPreferences {
        // MobiliteitKit preserves every GTFS mode. The app's preference remains
        // a presentation preference until the package's route-type mask has a
        // lossless representation for extended GTFS route types (e.g. 900).
        let modes: TransitModeMask = .all
        return RoutingPreferences(
            minimumTransferSeconds: filters.avoidTightTransfers ? 180 : 120,
            allowedModes: modes,
            wheelchair: filters.preferAccessible ? .required : .noPreference
        )
    }

    private nonisolated func option(from journey: MobiliteitKit.Journey, origin: LocationPoint, destination: LocationPoint) -> RouteOption {
        let legs = journey.legs.compactMap { leg -> RoutePlan.Leg? in
            switch leg {
            case let .walk(walk):
                return RoutePlan.Leg(
                    id: "walk-\(walk.departure.timeIntervalSince1970)", mode: .walking,
                    transportKind: .walking, origin: point(walk.from), destination: point(walk.to),
                    departureTime: walk.departure, arrivalTime: walk.arrival,
                    distanceMeters: walk.distanceMeters,
                    mapCoordinates: walk.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    roadRoutingHint: .walking
                )
            case let .transit(transit):
                let delayed = transit.effectiveDeparture > transit.scheduledDeparture || transit.effectiveArrival > transit.scheduledArrival
                return RoutePlan.Leg(
                    id: "transit-\(transit.tripID)-\(transit.board.stop.id)-\(transit.alight.stop.id)",
                    mode: mode(transit.route.type), transportKind: .transit,
                    routeName: transit.route.shortName ?? transit.route.longName,
                    headsign: transit.headsign, routeId: transit.route.id, tripId: transit.tripID,
                    originStopId: transit.board.stop.id, destinationStopId: transit.alight.stop.id,
                    stopCount: transit.intermediateStops.count + 1,
                    origin: point(transit.board.stop), destination: point(transit.alight.stop),
                    departureTime: transit.effectiveDeparture, arrivalTime: transit.effectiveArrival,
                    scheduledDepartureTime: transit.scheduledDeparture, scheduledArrivalTime: transit.scheduledArrival,
                    realtimeDepartureTime: delayed ? transit.effectiveDeparture : nil,
                    realtimeArrivalTime: delayed ? transit.effectiveArrival : nil,
                    platform: transit.board.platform,
                    delayMinutes: delayed ? Int(transit.effectiveDeparture.timeIntervalSince(transit.scheduledDeparture) / 60) : nil,
                    liveStatus: delayed ? .delayed : .scheduled
                )
            case .inSeatContinuation:
                return nil
            }
        }
        let plan = RoutePlan(id: journey.id.value, origin: origin, destination: destination,
                             expectedTravelTime: journey.duration, distanceMeters: journey.walkingDistance,
                             legs: legs, dataSource: .local)
        let overlay = RouteMapOverlay(segments: legs.compactMap { leg in
            guard leg.mapCoordinates.count >= 2 else { return nil }
            return RouteMapSegment(id: leg.id, mode: leg.mode, routeName: leg.routeName, routeId: leg.routeId, coordinates: leg.mapCoordinates)
        })
        return RouteOption(id: journey.id.value, plan: plan, mapOverlay: overlay.segments.isEmpty ? nil : overlay)
    }

    private nonisolated func point(_ source: MobiliteitKit.TransitStop) -> LocationPoint { .init(id: source.id, name: source.name, latitude: source.coordinate.latitude, longitude: source.coordinate.longitude) }
    private nonisolated func point(_ source: JourneyLocation) -> LocationPoint { .init(id: source.stop?.id, name: source.label ?? source.stop?.name, latitude: source.coordinate.latitude, longitude: source.coordinate.longitude) }
    private nonisolated func mode(_ value: Int) -> TransportMode { switch value { case 0...2: .train; case 3, 700...799: .bus; case 900...999: .tram; case 7: .funicular; default: .unknown } }
}

private struct MapKitWalkingProvider: WalkingRoutingProvider {
    func estimate(_ request: WalkingRequest) async throws -> WalkingEstimate {
        let route = try await route(request)
        return .init(durationSeconds: route.durationSeconds, distanceMeters: route.distanceMeters)
    }

    func route(_ request: WalkingRequest) async throws -> WalkingRoute {
        let directions = MKDirections(request: walkingRequest(request))
        let value = try await directions.calculate()
        guard let route = value.routes.first else { throw RoutingError.noRouteFound }
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
        return .init(durationSeconds: Int(route.expectedTravelTime.rounded()), distanceMeters: route.distance,
                     polyline: coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                     steps: route.steps.map { .init(instruction: $0.instructions) })
    }

    private func walkingRequest(_ value: WalkingRequest) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: value.source.latitude, longitude: value.source.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: value.destination.latitude, longitude: value.destination.longitude), address: nil)
        request.transportType = .walking
        request.departureDate = value.departure
        return request
    }
}
