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
}
