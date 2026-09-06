import Foundation

nonisolated struct GTFSTimetableIndexPayload: Codable, Sendable, Hashable {
    /// Version 3 guarantees every installed feed includes the `shapes.txt`
    /// geometry referenced by its trips. Bump this so indexes produced while
    /// large shapes were skipped are rebuilt from the retained GTFS archive.
    static let currentVersion = 3
    var schemaVersion: Int? = currentVersion
    var revision: String? = nil
    let source: String
    let stops: [GTFSTimetableStopEntry]
    let routes: [GTFSTimetableRouteEntry]
    let services: [GTFSTimetableServiceEntry]
    let trips: [GTFSTimetableTripEntry]
    let transfers: [GTFSTimetableTransferEntry]
    let shapes: [GTFSTimetableShapeEntry]
}

nonisolated struct GTFSTimetableStopEntry: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let parentStation: String?
    let platformCode: String?

    var location: LocationPoint {
        LocationPoint(id: id, name: name, latitude: latitude, longitude: longitude)
    }
}

nonisolated struct GTFSTimetableRouteEntry: Codable, Sendable, Hashable {
    let id: String
    let shortName: String
    let longName: String?
    let mode: String
    let operatorName: String?

    var transportMode: TransportMode {
        TransportMode(rawValue: mode) ?? .unknown
    }
}

nonisolated struct GTFSTimetableServiceEntry: Codable, Sendable, Hashable {
    let id: String
    let weekdays: Set<Int>
    let startDate: String?
    let endDate: String?
    let addedDates: Set<String>
    let removedDates: Set<String>
}

nonisolated struct GTFSTimetableTripEntry: Codable, Sendable, Hashable {
    let id: String
    let routeId: String
    let serviceId: String
    let headsign: String?
    let directionId: String?
    let shapeId: String?
    var originalTripID: String? = nil
    var serviceDate: String? = nil
    let stopTimes: [GTFSTimetableStopTimeEntry]
}

nonisolated struct GTFSTimetableStopTimeEntry: Codable, Sendable, Hashable {
    let stopId: String
    let arrivalSeconds: Int
    let departureSeconds: Int
    let sequence: Int
    let headsign: String?
    let pickupType: String?
    let dropOffType: String?
    let shapeDistanceTraveled: Double?
    var scheduledArrivalSeconds: Int? = nil
    var scheduledDepartureSeconds: Int? = nil
    var arrivalSource: RouteTimingSource? = nil
    var departureSource: RouteTimingSource? = nil
    var livePlatform: String? = nil
}

nonisolated struct GTFSTimetableTransferEntry: Codable, Sendable, Hashable {
    let fromStopId: String
    let toStopId: String
    let minimumTransferSeconds: Int?
    var transferType: Int? = nil
    var fromRouteID: String? = nil
    var toRouteID: String? = nil
    var fromTripID: String? = nil
    var toTripID: String? = nil
}

nonisolated struct GTFSTimetableShapeEntry: Codable, Sendable, Hashable {
    let id: String
    let points: [GTFSTimetableShapePoint]
}

nonisolated struct GTFSTimetableShapePoint: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double
    let sequence: Int
    let distanceTraveled: Double?
}
