import Foundation

/// The application's single GTFS boundary.
///
/// It owns both the locally installed schedule feed and its update pipeline.
/// Feature code depends on its bounded query surface (`GTFSService`) rather
/// than coordinating a loader, updater, departure calculator, and line-detail
/// calculator independently. The data remains explicitly scheduled data; live
/// ATP/AVL overlays stay outside this controller.
nonisolated final class GTFSController: GTFSService {
    private let localFeed: LocalGTFSService
    private let updates: GTFSUpdateService

    /// Kept shared for routing services that are recreated by SwiftUI.
    let routeSearchContextCache: RouteSearchContextCache

    init(
        bundle: Bundle = .main,
        resourceName: String = "gtfs-compact",
        store: GTFSLocalStore = GTFSLocalStore(),
        updates: GTFSUpdateService? = nil,
        stops: [Stop]? = nil,
        routesByStopId: [String: [TransitRoute]]? = nil
    ) {
        let localFeed = LocalGTFSService(
            bundle: bundle,
            resourceName: resourceName,
            store: store,
            stops: stops,
            routesByStopId: routesByStopId
        )
        self.localFeed = localFeed
        self.updates = updates ?? GTFSUpdateService(store: store)
        routeSearchContextCache = localFeed.routeSearchContextCache
    }

    nonisolated func searchStops(query: String) async -> [Stop] {
        await localFeed.searchStops(query: query)
    }

    nonisolated func stopsForMap(
        center: LocationPoint,
        latitudeDelta: Double,
        longitudeDelta: Double,
        limit: Int
    ) async -> [Stop] {
        await localFeed.stopsForMap(
            center: center,
            latitudeDelta: latitudeDelta,
            longitudeDelta: longitudeDelta,
            limit: limit
        )
    }

    nonisolated func stop(id: String) async -> Stop? { await localFeed.stop(id: id) }
    nonisolated func allStops() async -> [Stop] { await localFeed.allStops() }
    nonisolated func routesForStop(id: String) async -> [TransitRoute] {
        await localFeed.routesForStop(id: id)
    }
    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload? {
        await localFeed.timetableIndex()
    }

    func updateSnapshot() async -> GTFSUpdateSnapshot { await updates.snapshot() }

    func checkForUpdates(now: Date = .now) async -> GTFSUpdateSnapshot {
        await updates.checkForUpdates(now: now)
    }
}
