import Foundation

/// Deterministic transit fixtures for SwiftUI previews and offline tests.
/// Production wiring always uses ``MobiliteitGTFSService`` and
/// ``MobiliteitLiveTransitService``; these actors deliberately perform no I/O.
actor FixtureGTFSService: GTFSService {
    let status: GTFSFeedStatus
    let stops: [Stop]
    let routesByStopID: [String: [TransitRoute]]
    let schedulesByStopID: [String: [OfflineScheduleDeparture]]
    let lineDetailsByRouteID: [String: LineDetail]
    let departuresByStopID: [String: [GTFSJourneyDeparture]]
    let stopsByTripID: [String: [GTFSJourneyStopTime]]
    let transferRulesByStopID: [String: [GTFSTransferRule]]
    let shapesByTripID: [String: [RouteMapCoordinate]]

    init(
        status: GTFSFeedStatus = .unavailable,
        stops: [Stop] = [],
        routesByStopID: [String: [TransitRoute]] = [:],
        schedulesByStopID: [String: [OfflineScheduleDeparture]] = [:],
        lineDetailsByRouteID: [String: LineDetail] = [:],
        departuresByStopID: [String: [GTFSJourneyDeparture]] = [:],
        stopsByTripID: [String: [GTFSJourneyStopTime]] = [:],
        transferRulesByStopID: [String: [GTFSTransferRule]] = [:],
        shapesByTripID: [String: [RouteMapCoordinate]] = [:]
    ) {
        self.status = status
        self.stops = stops
        self.routesByStopID = routesByStopID
        self.schedulesByStopID = schedulesByStopID
        self.lineDetailsByRouteID = lineDetailsByRouteID
        self.departuresByStopID = departuresByStopID
        self.stopsByTripID = stopsByTripID
        self.transferRulesByStopID = transferRulesByStopID
        self.shapesByTripID = shapesByTripID
    }

    func refreshIfNeeded(force _: Bool) async -> GTFSFeedStatus { status }
    func feedStatus() async -> GTFSFeedStatus { status }

    func searchStops(query: String) async -> [Stop] {
        let normalized = query.normalizedForSearch
        guard !normalized.isEmpty else { return [] }
        return stops.filter { $0.fullName.normalizedForSearch.contains(normalized) }
    }

    func nearbyStops(to _: LocationPoint, radiusMeters _: Double, limit: Int) async -> [Stop] {
        Array(stops.prefix(max(0, limit)))
    }

    func matchLiveStop(_ liveStop: LiveTransitStop) async -> Stop? {
        let candidates = stops.filter { $0.name.normalizedForSearch == liveStop.name.normalizedForSearch }
        guard candidates.count == 1, let stop = candidates.first else { return nil }
        return Stop(
            id: stop.id,
            name: stop.name,
            locality: stop.locality,
            location: stop.location,
            modes: liveStop.modes.isEmpty ? stop.modes : liveStop.modes,
            dataSource: .gtfs,
            platformIds: stop.platformIds,
            wheelchairBoarding: stop.wheelchairBoarding,
            gtfsStopID: stop.gtfsStopID,
            hafasStationIDs: [liveStop.stationID]
        )
    }

    func routes(for stop: Stop) async -> [TransitRoute] { routesByStopID[stop.id] ?? [] }

    func scheduledDepartures(for stop: Stop, at _: Date, limit: Int) async -> [OfflineScheduleDeparture] {
        Array((schedulesByStopID[stop.id] ?? []).prefix(max(0, limit)))
    }

    func lineDetail(for route: TransitRoute, directionID _: String?, at _: Date) async -> LineDetail? {
        lineDetailsByRouteID[route.id]
    }

    func routingStops(near _: LocationPoint, radiusMeters _: Double, limit: Int) async -> [Stop] {
        Array(stops.prefix(max(0, limit)))
    }

    func journeyDepartures(from stop: Stop, after _: Date, horizon _: TimeInterval, limit: Int) async -> [GTFSJourneyDeparture] {
        Array((departuresByStopID[stop.id] ?? []).prefix(max(0, limit)))
    }

    func journeyStops(for tripID: String) async -> [GTFSJourneyStopTime] { stopsByTripID[tripID] ?? [] }
    func transferRules(from stop: Stop) async -> [GTFSTransferRule] { transferRulesByStopID[stop.id] ?? [] }
    func routeShape(for tripID: String) async -> [RouteMapCoordinate] { shapesByTripID[tripID] ?? [] }
}

actor FixtureLiveTransitService: LiveTransitService {
    let isConfigured: Bool
    let nearbyResults: [LiveTransitStop]
    let boardsByStationID: [String: [Departure]]
    let error: LiveTransitError?

    init(
        isConfigured: Bool = true,
        nearbyResults: [LiveTransitStop] = [],
        boardsByStationID: [String: [Departure]] = [:],
        error: LiveTransitError? = nil
    ) {
        self.isConfigured = isConfigured
        self.nearbyResults = nearbyResults
        self.boardsByStationID = boardsByStationID
        self.error = error
    }

    func nearbyStops(to _: LocationPoint, radiusMeters _: Int, limit: Int) async throws -> [LiveTransitStop] {
        if let error { throw error }
        return Array(nearbyResults.prefix(max(0, limit)))
    }

    func departureBoard(for stop: Stop, filter _: TransitBoardFilter) async throws -> [Departure] {
        if let error { throw error }
        guard let stationID = stop.hafasStationIDs.first else {
            throw LiveTransitError.noLiveIdentifier
        }
        return boardsByStationID[stationID] ?? []
    }
}
