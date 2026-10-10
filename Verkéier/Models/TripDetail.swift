import Foundation

/// Structured instance identity survives route refreshes and overnight services.
nonisolated struct TripRunIdentity: Codable, Hashable, Sendable {
    let feedGeneration: Int
    let tripID: String
    let serviceDate: String
}

nonisolated struct TripDetailSelection: Hashable, Sendable {
    let instance: TripRunIdentity
    let boardingSequence: Int
    let alightingSequence: Int
    let lineName: String
    let routeShortName: String?
    let headsign: String?
    let mode: TransportMode
    let routeID: String?
    let rideCoordinates: [RouteMapCoordinate]

    init?(leg: RoutePlan.Leg) {
        guard leg.transportKind == .transit, let instance = leg.tripInstance,
              let boarding = leg.boardingStopSequence, let alighting = leg.alightingStopSequence, boarding <= alighting else { return nil }
        self.instance = instance
        boardingSequence = boarding
        alightingSequence = alighting
        lineName = leg.routeName ?? leg.mode.displayName
        routeShortName = leg.routeShortName
        headsign = leg.headsign
        mode = leg.mode
        routeID = leg.routeId
        rideCoordinates = leg.mapCoordinates
    }
}

nonisolated struct TripStopTiming: Hashable, Sendable {
    let scheduled: Date
    let realtime: Date?
    let isHistoricalReport: Bool
    let observedAt: Date?
    let isCancelled: Bool
}

nonisolated struct TripStopEntry: Identifiable, Hashable, Sendable {
    let sequence: Int
    let stop: Stop
    let arrival: TripStopTiming?
    let departure: TripStopTiming?
    let platform: String?
    var id: Int { sequence }
}

nonisolated struct TripDetailSnapshot: Hashable, Sendable {
    let instance: TripRunIdentity
    let stops: [TripStopEntry]
    let mapOverlay: RouteMapOverlay
    let isApproximateRoute: Bool
    let liveDataAvailable: Bool
    let isCancelled: Bool
    let fetchedAt: Date
}
