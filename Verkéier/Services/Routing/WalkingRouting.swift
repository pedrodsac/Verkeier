import CoreLocation
import Foundation

/// The provenance of an on-foot calculation. This remains in the domain model
/// so persisted routes retain provenance. Legacy cases remain decodable;
/// production walking calculations use only the local pedestrian graph.
nonisolated enum WalkingEstimateSource: String, Codable, Sendable {
    case localOSM
    case mapKit
    case straightLineEstimate
}

/// A destination in a one-to-many walking query.
nonisolated struct WalkingDestination: Hashable, Sendable {
    let id: String
    let location: LocationPoint

    init(id: String, location: LocationPoint) {
        self.id = id
        self.location = location
    }
}

/// A source in a many-to-one walking query.
nonisolated struct WalkingOrigin: Hashable, Sendable {
    let id: String
    let location: LocationPoint
}

/// The distance and duration to one destination.
nonisolated struct OfflineWalkingEstimate: Hashable, Sendable {
    let destinationID: String
    let distanceMeters: Double
    let duration: TimeInterval
    let source: WalkingEstimateSource

    init(
        destinationID: String,
        distanceMeters: Double,
        duration: TimeInterval,
        source: WalkingEstimateSource
    ) {
        self.destinationID = destinationID
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.source = source
    }
}

/// A full walking path for rendering above the Apple Maps basemap.
nonisolated struct OfflineWalkingRoute: Hashable, Sendable {
    let distanceMeters: Double
    let duration: TimeInterval
    let coordinates: [RouteMapCoordinate]
    let source: WalkingEstimateSource

    init(
        distanceMeters: Double,
        duration: TimeInterval,
        coordinates: [RouteMapCoordinate],
        source: WalkingEstimateSource
    ) {
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.coordinates = coordinates
        self.source = source
    }
}

/// A walking-routing engine. Implementations are deliberately independent of
/// the UI and backed by the installed pedestrian graph in production.
nonisolated protocol WalkingRouting: Sendable {
    func checkAvailability() async throws
    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate]

    func estimates(
        from origins: [WalkingOrigin],
        to destination: LocationPoint
    ) async throws -> [OfflineWalkingEstimate]

    func route(
        from origin: LocationPoint,
        to destination: LocationPoint
    ) async throws -> OfflineWalkingRoute
}

nonisolated extension WalkingRouting {
    func checkAvailability() async throws {}

    func estimates(
        from origins: [WalkingOrigin],
        to destination: LocationPoint
    ) async throws -> [OfflineWalkingEstimate] {
        guard !origins.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: OfflineWalkingEstimate.self) { group in
            let limit = min(4, origins.count)
            var next = 0
            var results: [OfflineWalkingEstimate] = []
            func add(_ index: Int) {
                let origin = origins[index]
                group.addTask {
                    let route = try await route(from: origin.location, to: destination)
                    return .init(
                        destinationID: origin.id,
                        distanceMeters: route.distanceMeters,
                        duration: route.duration,
                        source: route.source
                    )
                }
            }
            for _ in 0..<limit { add(next); next += 1 }
            for try await result in group {
                results.append(result)
                if next < origins.count { add(next); next += 1 }
            }
            return results
        }
    }
}

nonisolated enum WalkingRoutingError: Error, Equatable {
    case datasetUnavailable
    case invalidResponse
    case noRoute
}

/// Real-world walking includes crossings, wayfinding, and brief pauses that
/// graph engines usually do not model. Apply one product-wide buffer so route
/// cards, transfer planning, and nearby-stop estimates agree.
nonisolated enum WalkingDurationCalibration {
    static let multiplier = 1.25

    static func adjusted(_ duration: TimeInterval) -> TimeInterval {
        max(1, duration * multiplier)
    }
}

/// Configures the inexpensive geographic prefilter before one matrix request.
nonisolated struct NearbyStopPrefilter: Sendable {
    let candidateLimit: Int
    let maximumStraightLineDistanceMeters: CLLocationDistance

    init(
        candidateLimit: Int = 40,
        maximumStraightLineDistanceMeters: CLLocationDistance = 5_000
    ) {
        self.candidateLimit = max(1, candidateLimit)
        self.maximumStraightLineDistanceMeters = max(0, maximumStraightLineDistanceMeters)
    }

    func destinations(from stops: [Stop], origin: LocationPoint) -> [WalkingDestination] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return stops
            .map { stop in
                (
                    stop: stop,
                    distance: originLocation.distance(from: CLLocation(
                        latitude: stop.location.latitude,
                        longitude: stop.location.longitude
                    ))
                )
            }
            .filter { $0.distance <= maximumStraightLineDistanceMeters }
            .sorted { $0.distance < $1.distance }
            .prefix(candidateLimit)
            .map { WalkingDestination(id: $0.stop.id, location: $0.stop.location) }
    }
}

nonisolated extension OfflineWalkingEstimate {
    var formattedDistance: String {
        Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var formattedDuration: String {
        Duration.seconds(duration).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}
