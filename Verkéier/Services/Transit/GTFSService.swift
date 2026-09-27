import Foundation

/// Static timetable access used by map, search, stop, line-detail, and routing
/// surfaces. Implementations keep the MobilitéitKit SQLite actor behind app
/// domain values so views never depend on a feed schema.
protocol GTFSService: Sendable {
    func refreshIfNeeded(force: Bool) async -> GTFSFeedStatus
    func feedStatus() async -> GTFSFeedStatus
    func searchStops(query: String) async -> [Stop]
    func nearbyStops(to location: LocationPoint, radiusMeters: Double, limit: Int) async -> [Stop]
    func matchLiveStop(_ liveStop: LiveTransitStop) async -> Stop?
    func routes(for stop: Stop) async -> [TransitRoute]
    func scheduledDepartures(for stop: Stop, at date: Date, limit: Int) async -> [OfflineScheduleDeparture]
    func lineDetail(for route: TransitRoute, directionID: String?, at date: Date) async -> LineDetail?
    func routingStops(near location: LocationPoint, radiusMeters: Double, limit: Int) async -> [Stop]
    func journeyDepartures(from stop: Stop, after date: Date, horizon: TimeInterval, limit: Int) async -> [GTFSJourneyDeparture]
    func journeyStops(for tripID: String) async -> [GTFSJourneyStopTime]
    func transferRules(from stop: Stop) async -> [GTFSTransferRule]
    func routeShape(for tripID: String) async -> [RouteMapCoordinate]
    func routeShapes(for tripIDs: [String]) async -> [String: [RouteMapCoordinate]]
}

extension GTFSService {
    func routeShapes(for tripIDs: [String]) async -> [String: [RouteMapCoordinate]] {
        var shapes: [String: [RouteMapCoordinate]] = [:]
        for tripID in Set(tripIDs) {
            let shape = await routeShape(for: tripID)
            if shape.count >= 2 { shapes[tripID] = shape }
        }
        return shapes
    }
}

nonisolated enum GTFSFeedPhase: String, Codable, Sendable {
    case unavailable
    case checking
    case downloading
    case ready
    /// A previously valid feed remains usable, but its most recent check or
    /// update did not complete. The UI must not mistake it for fresh data.
    case stale
    case failed
}

nonisolated struct GTFSFeedStatus: Codable, Sendable, Equatable {
    var phase: GTFSFeedPhase
    var resourceTitle: String?
    var downloadedAt: Date?
    var lastCheckedAt: Date?
    var releasedAt: Date?
    var validThrough: String?
    var errorMessage: String?

    nonisolated static let unavailable = GTFSFeedStatus(phase: .unavailable)

    var isReady: Bool { phase == .ready || phase == .stale }
    var statusText: String {
        switch phase {
        case .ready: "Ready"
        case .checking: "Checking"
        case .downloading: "Updating"
        case .stale: "Cached; update failed"
        case .failed: "Update failed"
        case .unavailable: "Not downloaded"
        }
    }
}

struct GTFSJourneyDeparture: Sendable, Hashable {
    let tripID: String
    let stopID: String
    let route: TransitRoute
    let headsign: String
    let directionID: Int?
    let departureDate: Date
    let arrivalDate: Date?
}

struct GTFSJourneyStopTime: Sendable, Hashable {
    let stop: Stop
    let sequence: Int
    let arrivalDate: Date?
    let departureDate: Date?
    let pickupAllowed: Bool
    let dropOffAllowed: Bool
}

struct GTFSTransferRule: Sendable, Hashable {
    let destinationStopID: String
    let minimumTransferSeconds: Int?
}

struct UnavailableGTFSService: GTFSService {
    func refreshIfNeeded(force _: Bool) async -> GTFSFeedStatus { .unavailable }
    func feedStatus() async -> GTFSFeedStatus { .unavailable }
    func searchStops(query _: String) async -> [Stop] { [] }
    func nearbyStops(to _: LocationPoint, radiusMeters _: Double, limit _: Int) async -> [Stop] { [] }
    func matchLiveStop(_: LiveTransitStop) async -> Stop? { nil }
    func routes(for _: Stop) async -> [TransitRoute] { [] }
    func scheduledDepartures(for _: Stop, at _: Date, limit _: Int) async -> [OfflineScheduleDeparture] { [] }
    func lineDetail(for _: TransitRoute, directionID _: String?, at _: Date) async -> LineDetail? { nil }
    func routingStops(near _: LocationPoint, radiusMeters _: Double, limit _: Int) async -> [Stop] { [] }
    func journeyDepartures(from _: Stop, after _: Date, horizon _: TimeInterval, limit _: Int) async -> [GTFSJourneyDeparture] { [] }
    func journeyStops(for _: String) async -> [GTFSJourneyStopTime] { [] }
    func transferRules(from _: Stop) async -> [GTFSTransferRule] { [] }
    func routeShape(for _: String) async -> [RouteMapCoordinate] { [] }
}
