import Foundation
import Valhalla
import ValhallaConfigModels
import ValhallaModels

/// Serialized adapter around one Valhalla instance and one immutable tile
/// archive. Valhalla's native actor is not safe for concurrent requests; this
/// Swift actor also ensures the work never runs on the main actor.
actor ValhallaWalkingRouter: WalkingRouting {
    private let engine: Valhalla

    init(tileArchiveURL: URL, datasetVersion: String) throws {
        guard FileManager.default.fileExists(atPath: tileArchiveURL.path) else {
            throw WalkingRoutingError.datasetUnavailable
        }
        let config = try ValhallaConfig(tileExtractTar: tileArchiveURL)
        engine = try Valhalla(config, configName: "verkeier-valhalla-\(datasetVersion).json")
    }

    func estimates(
        from origin: LocationPoint,
        to destinations: [WalkingDestination]
    ) async throws -> [OfflineWalkingEstimate] {
        guard !destinations.isEmpty else { return [] }
        var estimates: [OfflineWalkingEstimate] = []
        for destination in destinations {
            try Task.checkCancellation()
            do {
                let path = try await route(from: origin, to: destination.location)
                estimates.append(.init(
                    destinationID: destination.id,
                    distanceMeters: path.distanceMeters,
                    duration: path.duration,
                    source: .localOSM
                ))
            } catch WalkingRoutingError.noRoute {
                continue
            }
        }
        return estimates
    }

    func estimates(
        from origins: [WalkingOrigin],
        to destination: LocationPoint
    ) async throws -> [OfflineWalkingEstimate] {
        guard !origins.isEmpty else { return [] }
        var estimates: [OfflineWalkingEstimate] = []
        for origin in origins {
            try Task.checkCancellation()
            do {
                let path = try await route(from: origin.location, to: destination)
                estimates.append(.init(
                    destinationID: origin.id,
                    distanceMeters: path.distanceMeters,
                    duration: path.duration,
                    source: .localOSM
                ))
            } catch WalkingRoutingError.noRoute {
                continue
            }
        }
        return estimates
    }

    func route(
        from origin: LocationPoint,
        to destination: LocationPoint
    ) async throws -> OfflineWalkingRoute {
        let request = RouteRequest(
            locations: [
                RoutingWaypoint(lat: origin.latitude, lon: origin.longitude),
                RoutingWaypoint(lat: destination.latitude, lon: destination.longitude),
            ],
            costing: .pedestrian,
            units: .km,
            directionsType: .none,
            shapeFormat: .polyline6
        )
        let response = try engine.route(request: request)
        guard response.trip.status == 0,
              response.trip.summary.length.isFinite,
              response.trip.summary.length >= 0
        else {
            throw WalkingRoutingError.noRoute
        }

        let coordinates = try response.trip.legs.flatMap { try Self.decodePolyline6($0.shape) }
            .removingConsecutiveDuplicates()
        guard coordinates.count >= 2 else { throw WalkingRoutingError.invalidResponse }

        return OfflineWalkingRoute(
            distanceMeters: Self.meters(from: response.trip.summary.length, units: response.trip.units),
            duration: response.trip.summary.time,
            coordinates: coordinates,
            source: .localOSM
        )
    }

    nonisolated private static func meters(from distance: Double, units: ValhallaLongUnits) -> Double {
        switch units {
        case .kilometers: distance * 1_000
        case .miles: distance * 1_609.344
        }
    }

    /// Decodes Valhalla's documented six-decimal encoded path format.
    nonisolated static func decodePolyline6(_ shape: String) throws -> [RouteMapCoordinate] {
        var coordinates: [RouteMapCoordinate] = []
        var index = shape.startIndex
        var latitude = 0
        var longitude = 0

        func component() throws -> Int {
            var value = 0
            var shift = 0
            while true {
                guard index < shape.endIndex else { throw WalkingRoutingError.invalidResponse }
                let scalar = shape[index].unicodeScalars.first!.value
                guard scalar >= 63 else { throw WalkingRoutingError.invalidResponse }
                index = shape.index(after: index)
                let byte = Int(scalar - 63)
                value |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { break }
                guard shift <= 30 else { throw WalkingRoutingError.invalidResponse }
            }
            return value & 1 == 0 ? value >> 1 : ~(value >> 1)
        }

        while index < shape.endIndex {
            latitude += try component()
            longitude += try component()
            coordinates.append(RouteMapCoordinate(
                latitude: Double(latitude) / 1_000_000,
                longitude: Double(longitude) / 1_000_000
            ))
        }
        return coordinates
    }
}

private extension Array where Element == RouteMapCoordinate {
    nonisolated func removingConsecutiveDuplicates() -> [RouteMapCoordinate] {
        reduce(into: []) { result, coordinate in
            guard result.last != coordinate else { return }
            result.append(coordinate)
        }
    }
}
