import CoreLocation
import Foundation
import MobiliteitKit

/// Supplements the pedestrian graph with the unscheduled Pafendall station link.
/// Track: OSM ways 272711527, 682347528, 466675117, 542307098,
/// 466675116 and 682347529 (track A); see docs/PAFENDALL_FUNICULAR.md.
nonisolated enum PafendallFunicularConnection {
    static let revision = "pafendall-funicular-v1"
    static let rideSeconds = 63
    // Product allowance for reaching a cabin and boarding, separate from the
    // walking calibration and the transit router's train boarding buffer.
    static let boardingSeconds = 60
    static let upper = LocationPoint(name: "Rout Bréck-Pafendall, Funicular",
                                    latitude: 49.6189108, longitude: 6.1358874)
    static let lower = LocationPoint(name: "Pfaffenthal-Kirchberg, Funicular",
                                    latitude: 49.6189879, longitude: 6.1327721)
    private static let tram = LocationPoint(latitude: 49.618697, longitude: 6.136686)
    private static let rail = LocationPoint(latitude: 49.618936, longitude: 6.132919)
    private static let track: [Coordinate] = [
        .init(latitude: 49.6189108, longitude: 6.1358874),
        .init(latitude: 49.6189181, longitude: 6.1356216),
        .init(latitude: 49.6189347, longitude: 6.1350012),
        .init(latitude: 49.6189459, longitude: 6.1348646),
        .init(latitude: 49.6189714, longitude: 6.1345320),
        .init(latitude: 49.6189830, longitude: 6.1341615),
        .init(latitude: 49.6189679, longitude: 6.1337268),
        .init(latitude: 49.6189785, longitude: 6.1332098),
        .init(latitude: 49.6189879, longitude: 6.1327721)
    ]

    /// Only cross-level journeys within this interchange qualify. Nearby streets
    /// on the same level retain their ordinary pedestrian route.
    static func terminals(from: LocationPoint, to: LocationPoint) -> (LocationPoint, LocationPoint)? {
        if distance(from, tram) <= 120, distance(to, rail) <= 100 { return (upper, lower) }
        if distance(from, rail) <= 100, distance(to, tram) <= 120 { return (lower, upper) }
        return nil
    }

    static func route(
        from: LocationPoint, to: LocationPoint,
        pedestrian: @Sendable (LocationPoint, LocationPoint) async throws -> OfflineWalkingRoute
    ) async throws -> OfflineWalkingRoute? {
        guard let (board, alight) = terminals(from: from, to: to) else { return nil }
        let access = try await pedestrian(from, board)
        let egress = try await pedestrian(alight, to)
        guard access.source == .localOSM, egress.source == .localOSM else { return nil }
        let ridePath = board == upper ? track : Array(track.reversed())
        let rideDistance = zip(ridePath, ridePath.dropFirst()).reduce(0.0) {
            $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude)
                .distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude))
        }
        func walking(_ route: OfflineWalkingRoute, from: LocationPoint, to: LocationPoint) -> WalkingRouteSegment {
            .init(mode: .walking, originLabel: from.name, destinationLabel: to.name,
                  durationSeconds: max(1, Int(route.duration.rounded())),
                  distanceMeters: route.distanceMeters,
                  polyline: [Coordinate(latitude: from.latitude, longitude: from.longitude)]
                    + route.coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
                    + [Coordinate(latitude: to.latitude, longitude: to.longitude)])
        }
        let segments = [walking(access, from: from, to: board),
            WalkingRouteSegment(mode: .funicular, name: "Funicular",
                originLabel: board.name, destinationLabel: alight.name,
                durationSeconds: rideSeconds + boardingSeconds,
                distanceMeters: rideDistance, polyline: ridePath),
            walking(egress, from: alight, to: to)]
        return .init(distanceMeters: segments.reduce(0) { $0 + $1.distanceMeters },
                     duration: Double(segments.reduce(0) { $0 + $1.durationSeconds }),
                     coordinates: segments.flatMap(\.polyline).map {
                         .init(latitude: $0.latitude, longitude: $0.longitude)
                     }, source: .stationConnection, segments: segments)
    }

    private static func distance(_ a: LocationPoint, _ b: LocationPoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
