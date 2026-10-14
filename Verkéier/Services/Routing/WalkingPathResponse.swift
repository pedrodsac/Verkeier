import Foundation
import ValhallaModels

/// Valhalla omits maneuver fields when directions_type is "none". Walking
/// calculations consume only measured timing, distance and the encoded path.
nonisolated struct WalkingPathResponse: Decodable {
    struct Summary: Decodable { let length: Double; let time: Double }
    struct Leg: Decodable { let shape: String }
    enum Units: String, Decodable { case kilometers, miles }
    struct Trip: Decodable {
        let status: Int
        let summary: Summary
        let units: Units
        let legs: [Leg]
    }
    let trip: Trip

    static func route(from data: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> OfflineWalkingRoute {
        let trip = try decoder.decode(Self.self, from: data).trip
        guard trip.status == 0, trip.summary.length.isFinite, trip.summary.length >= 0,
            trip.summary.time.isFinite, trip.summary.time >= 0
        else { throw WalkingRoutingError.noRoute }
        var coordinates: [RouteMapCoordinate] = []
        for leg in trip.legs {
            for coordinate in try ValhallaWalkingRouter.decodePolyline6(leg.shape) where coordinates.last != coordinate
            {
                coordinates.append(coordinate)
            }
        }
        guard coordinates.count >= 2 else { throw WalkingRoutingError.invalidResponse }
        return .init(
            distanceMeters: trip.summary.length * (trip.units == .kilometers ? 1_000 : 1_609.344),
            duration: trip.summary.time,
            coordinates: coordinates,
            source: .localOSM
        )
    }
}

nonisolated enum WalkingPathRequest {
    static func make(
        from origin: LocationPoint,
        to destination: LocationPoint,
        minimumReachability: Int
    ) -> RouteRequest {
        func waypoint(_ location: LocationPoint) -> RoutingWaypoint {
            // Use the matching native defaults instead of encoding the same
            // tolerances and candidate flags for thousands of endpoints.
            .init(
                lat: location.latitude,
                lon: location.longitude,
                headingTolerance: nil,
                minimumReachability: minimumReachability,
                radius: nil,
                rankCandidates: nil,
                nodeSnapTolerance: nil,
                streetSideTolerance: nil,
                streetSideMaxDistance: nil
            )
        }
        return RouteRequest(
            locations: [waypoint(origin), waypoint(destination)],
            costing: .pedestrian,
            units: .km,
            directionsType: ._none,
            shapeFormat: .polyline6
        )
    }
}
