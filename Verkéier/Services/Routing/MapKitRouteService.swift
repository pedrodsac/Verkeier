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
        // MapKit transit routing has no per-mode/sort hook, so filters are advisory only
        // here; MapKit owns the transit-mode selection.
        let request = MKDirections.Request()
        request.source = mapItem(for: from)
        request.destination = mapItem(for: to)
        request.transportType = [.transit, .walking]
        request.requestsAlternateRoutes = false
        let effectiveTime: RoutePlanningTime = switch page {
        case .initial:
            time
        case let .earlier(boundary, _):
            .arriveBy(boundary.addingTimeInterval(-1))
        case let .later(boundary, _):
            .departAt(boundary.addingTimeInterval(1))
        }
        switch effectiveTime {
        case .leaveNow: break
        case let .departAt(date): request.departureDate = date
        case let .arriveBy(date): request.arrivalDate = date
        }

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
            legs: Self.legs(from: route, origin: from, destination: to),
            dataSource: .mapKit
        )

        let option = RouteOption(
            id: "mapkit-\(from.id)-\(to.id)",
            plan: plan,
            mapOverlay: Self.overlay(from: route)
        )
        return RouteCalculation(options: [option], selectedOptionID: option.id)
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

    private nonisolated static func legs(
        from route: MKRoute,
        origin: LocationPoint,
        destination: LocationPoint
    ) -> [RoutePlan.Leg] {
        let routeName = route.name.isEmpty ? nil : route.name
        let stepLegs = route.steps.enumerated().compactMap { index, step -> RoutePlan.Leg? in
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty || step.distance > 0 else { return nil }

            let transportKind = RouteLegTransportKind(step.transportType)
            return RoutePlan.Leg(
                id: "mapkit-step-\(index)",
                mode: transportKind.transportMode,
                instruction: instruction.isEmpty ? nil : instruction,
                transportKind: transportKind,
                routeName: routeName,
                origin: origin,
                destination: destination,
                departureTime: nil,
                arrivalTime: nil,
                distanceMeters: step.distance > 0 ? step.distance : nil
            )
        }

        if !stepLegs.isEmpty {
            return stepLegs
        }

        return [
            RoutePlan.Leg(
                id: "mapkit-primary",
                mode: .unknown,
                instruction: nil,
                transportKind: .unknown,
                routeName: routeName,
                origin: origin,
                destination: destination,
                departureTime: nil,
                arrivalTime: nil,
                distanceMeters: route.distance
            )
        ]
    }

    private nonisolated static func overlay(from route: MKRoute) -> RouteMapOverlay {
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))

        return RouteMapOverlay(segments: [
            RouteMapSegment(
                id: "mapkit-route",
                mode: .unknown,
                coordinates: coordinates.map {
                    RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        ])
    }
}

private extension RouteLegTransportKind {
    nonisolated init(_ transportType: MKDirectionsTransportType) {
        if transportType.contains(.transit) {
            self = .transit
        } else if transportType.contains(.walking) {
            self = .walking
        } else if transportType.contains(.automobile) {
            self = .automobile
        } else {
            self = .unknown
        }
    }

    nonisolated var transportMode: TransportMode {
        switch self {
        case .walking: .walking
        case .bikeShare: .bicycle
        case .transit, .automobile, .unknown: .unknown
        }
    }
}
