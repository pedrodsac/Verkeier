import Foundation
import Valhalla
import ValhallaConfigModels
import ValhallaModels

/// Serialized adapter around one Valhalla instance and one immutable tile
/// archive. Valhalla's native actor is not safe for concurrent requests; this
/// Swift actor also ensures the work never runs on the main actor.
actor ValhallaWalkingRouter: WalkingRouting {
    private let engine: Valhalla
    private let requestEncoder = JSONEncoder()
    private let responseDecoder = JSONDecoder()

    init(tileArchiveURL: URL, datasetVersion: String) throws {
        guard FileManager.default.fileExists(atPath: tileArchiveURL.path) else {
            throw WalkingRoutingError.datasetUnavailable
        }
        VKConfigurePedestrianLogging()
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
                estimates.append(
                    .init(
                        destinationID: destination.id,
                        distanceMeters: path.distanceMeters,
                        duration: path.duration,
                        source: .localOSM
                    )
                )
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
                estimates.append(
                    .init(
                        destinationID: origin.id,
                        distanceMeters: path.distanceMeters,
                        duration: path.duration,
                        source: .localOSM
                    )
                )
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
        try await route(from: origin, to: destination, minimumReachability: 50)
    }

    private func route(
        from origin: LocationPoint,
        to destination: LocationPoint,
        minimumReachability: Int
    ) async throws -> OfflineWalkingRoute {
        let request = WalkingPathRequest.make(from: origin, to: destination, minimumReachability: minimumReachability)
        let data = try requestEncoder.encode(request)
        let response = try engine.route(rawRequest: String(decoding: data, as: UTF8.self))
        return try WalkingPathResponse.route(from: Data(response.utf8), using: responseDecoder)
    }

    func shortRoute(from origin: LocationPoint, to destination: LocationPoint) async throws -> OfflineWalkingRoute {
        try await ShortWalkingRouteSearch.route {
            try await self.route(from: origin, to: destination, minimumReachability: $0)
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
            coordinates.append(
                RouteMapCoordinate(
                    latitude: Double(latitude) / 1_000_000,
                    longitude: Double(longitude) / 1_000_000
                )
            )
        }
        return coordinates
    }
}
