import Foundation

nonisolated struct GTFSTimetableIndexPayload: Codable, Sendable, Hashable {
    /// Version 3 guarantees every installed feed includes the `shapes.txt`
    /// geometry referenced by its trips. Bump this so indexes produced while
    /// large shapes were skipped are rebuilt from the retained GTFS archive.
    /// Version 4 retains the GTFS fields which are not currently rendered by
    /// the app. Keeping them in the archive boundary makes them available to
    /// future features without another importer redesign.
    static let currentVersion = 4
    var schemaVersion: Int? = currentVersion
    var revision: String? = nil
    let source: String
    var agencies: [GTFSTimetableAgencyEntry] = []
    let stops: [GTFSTimetableStopEntry]
    let routes: [GTFSTimetableRouteEntry]
    let services: [GTFSTimetableServiceEntry]
    let trips: [GTFSTimetableTripEntry]
    let transfers: [GTFSTimetableTransferEntry]
    let shapes: [GTFSTimetableShapeEntry]
}

/// Operator facts published by `agency.txt`. These are deliberately separate
/// from presentation so missing contact/fare data is never invented by a UI.
nonisolated struct GTFSTimetableAgencyEntry: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let url: String?
    let timezone: String?
    var language: String? = nil
    var phone: String? = nil
    var fareURL: String? = nil
    var email: String? = nil
}

nonisolated struct GTFSTimetableStopEntry: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let parentStation: String?
    let platformCode: String?
    var code: String? = nil
    var description: String? = nil
    var locationType: Int? = nil
    /// Raw GTFS value. `0` means unknown, never "not accessible".
    var wheelchairBoarding: String? = nil

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
    var description: String? = nil
    var color: String? = nil
    var textColor: String? = nil

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
    var blockId: String? = nil
    /// Raw GTFS value. `0` means unknown, not disallowed.
    var wheelchairAccessible: String? = nil
    /// Raw GTFS value. `0` means unknown, not disallowed.
    var bikesAllowed: String? = nil
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
