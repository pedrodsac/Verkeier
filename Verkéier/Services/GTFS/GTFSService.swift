import Foundation

/// On-device access to the GTFS feed: stop search, map queries, route lookups,
/// and the offline timetable index.
///
/// All lookups resolve against locally stored data, so they never throw and
/// work offline. The production implementation is ``LocalGTFSService``, backed
/// by a bundled compact feed and any downloaded update.
protocol GTFSService: Sendable {
    /// Searches stops by name/locality. Returns `[]` for a blank query.
    nonisolated func searchStops(query: String) async -> [Stop]

    /// Returns stops within a map region, nearest first.
    /// - Parameters:
    ///   - center: Centre of the visible region.
    ///   - latitudeDelta: Latitude span of the region.
    ///   - longitudeDelta: Longitude span of the region.
    ///   - limit: Maximum number of stops to return.
    nonisolated func stopsForMap(center: LocationPoint, latitudeDelta: Double, longitudeDelta: Double, limit: Int) async -> [Stop]

    /// Looks up a single stop by identifier, or `nil` if unknown.
    nonisolated func stop(id: String) async -> Stop?

    /// Returns every stop in the feed.
    nonisolated func allStops() async -> [Stop]

    /// Returns the routes that serve a given stop.
    nonisolated func routesForStop(id: String) async -> [TransitRoute]

    /// Returns the offline timetable index, or `nil` if none is available yet.
    ///
    /// Used by ``OfflineScheduleService`` and ``LineDetailService`` to compute
    /// departures and line detail without a network connection.
    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload?

    /// A bounded, scheduled-only departure query. This is the preferred API
    /// for screens; callers should not retain or scan the timetable payload.
    nonisolated func scheduledDepartures(
        for stop: Stop,
        now: Date,
        limit: Int
    ) async -> [OfflineScheduleDeparture]

    /// A bounded route-detail query for the existing line-detail screen.
    nonisolated func lineDetail(
        for route: TransitRoute,
        selectedStopId: String?,
        now: Date,
        selectedDirectionID: String?
    ) async -> LineDetail?

    /// Archive facts intentionally exposed for future features, without
    /// requiring a new UI or leaking importer/database implementation types.
    nonisolated func archiveCapabilities() async -> GTFSArchiveCapabilities
    nonisolated func agencies() async -> [GTFSTimetableAgencyEntry]
    nonisolated func timetableRoute(id: String) async -> GTFSTimetableRouteEntry?
    nonisolated func timetableStop(id: String) async -> GTFSTimetableStopEntry?
    nonisolated func trip(id: String) async -> GTFSTimetableTripEntry?
    nonisolated func transferRules(for stopID: String) async -> [GTFSTimetableTransferEntry]
    nonisolated func shape(id: String) async -> GTFSTimetableShapeEntry?
}

extension GTFSService {
    nonisolated func scheduledDepartures(
        for stop: Stop,
        now: Date = .now,
        limit: Int = 8
    ) async -> [OfflineScheduleDeparture] {
        guard let timetable = await timetableIndex() else { return [] }
        return OfflineScheduleService().upcomingDepartures(
            for: stop, timetable: timetable, now: now, limit: limit
        )
    }

    nonisolated func lineDetail(
        for route: TransitRoute,
        selectedStopId: String? = nil,
        now: Date = .now,
        selectedDirectionID: String? = nil
    ) async -> LineDetail? {
        guard let timetable = await timetableIndex() else { return nil }
        return LineDetailService().detail(
            for: route,
            selectedStopId: selectedStopId,
            timetable: timetable,
            now: now,
            selectedDirectionID: selectedDirectionID
        )
    }

    nonisolated func archiveCapabilities() async -> GTFSArchiveCapabilities {
        guard let timetable = await timetableIndex() else { return .unavailable }
        return GTFSArchiveCapabilities(
            supportsScheduledDepartures: !timetable.trips.isEmpty,
            supportsScheduledArrivals: !timetable.trips.isEmpty,
            supportsTripGeometry: !timetable.shapes.isEmpty,
            supportsTransfers: !timetable.transfers.isEmpty,
            supportsBicycleInformation: timetable.trips.contains { $0.bikesAllowed == "1" },
            supportsBlockContinuity: timetable.trips.contains { $0.blockId?.isEmpty == false },
            supportsRealtime: false,
            supportsFares: false,
            supportsStationHierarchy: timetable.stops.contains { $0.parentStation?.isEmpty == false },
            supportsAccessibilityInformation: timetable.stops.contains { ["1", "2"].contains($0.wheelchairBoarding) }
        )
    }

    nonisolated func agencies() async -> [GTFSTimetableAgencyEntry] {
        await timetableIndex()?.agencies ?? []
    }

    nonisolated func timetableRoute(id: String) async -> GTFSTimetableRouteEntry? {
        await timetableIndex()?.routes.first { $0.id == id }
    }

    nonisolated func timetableStop(id: String) async -> GTFSTimetableStopEntry? {
        await timetableIndex()?.stops.first { $0.id == id }
    }

    nonisolated func trip(id: String) async -> GTFSTimetableTripEntry? {
        await timetableIndex()?.trips.first { $0.id == id }
    }

    nonisolated func transferRules(for stopID: String) async -> [GTFSTimetableTransferEntry] {
        await timetableIndex()?.transfers.filter {
            $0.fromStopId == stopID || $0.toStopId == stopID
        } ?? []
    }

    nonisolated func shape(id: String) async -> GTFSTimetableShapeEntry? {
        await timetableIndex()?.shapes.first { $0.id == id }
    }
}
