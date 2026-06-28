import Foundation

/// The production ``GTFSService``, serving stops, routes, and the timetable
/// index from on-device data.
///
/// Data is loaded lazily into an internal actor-isolated snapshot, preferring a
/// downloaded GTFS update on disk and falling back to the bundled compact feed.
/// The service observes the `gtfsDidUpdate` notification and reloads its
/// snapshot when a fresh feed is installed.
final class LocalGTFSService: GTFSService {
    private let loader: GTFSDataLoader
    private let updateTask: Task<Void, Never>

    init(
        bundle: Bundle = .main,
        resourceName: String = "gtfs-compact",
        store: GTFSLocalStore = GTFSLocalStore(),
        stops: [Stop]? = nil,
        routesByStopId: [String: [TransitRoute]]? = nil
    ) {
        let initialSnapshot: GTFSSnapshot? = if let stops, let routesByStopId {
            GTFSSnapshot(
                stops: stops,
                routesByStopId: routesByStopId,
                timetable: nil
            )
        } else {
            nil
        }

        let loader = GTFSDataLoader(
            bundle: bundle,
            resourceName: resourceName,
            store: store,
            initialSnapshot: initialSnapshot
        )
        self.loader = loader
        updateTask = Task { [loader] in
            for await _ in NotificationCenter.default.notifications(named: .gtfsDidUpdate) {
                await loader.reloadFromDisk()
            }
        }
    }

    deinit {
        updateTask.cancel()
    }

    nonisolated func searchStops(query: String) async -> [Stop] {
        let normalizedQuery = query.normalizedForSearch
        guard !normalizedQuery.isEmpty else { return [] }

        return await loader.searchStops(query: normalizedQuery)
    }

    nonisolated func stopsForMap(
        center: LocationPoint,
        latitudeDelta: Double,
        longitudeDelta: Double,
        limit: Int
    ) async -> [Stop] {
        let effectiveLimit = max(0, limit)
        guard effectiveLimit > 0 else { return [] }

        let latitudeRadius = max(latitudeDelta / 2, 0.01)
        let longitudeRadius = max(longitudeDelta / 2, 0.01)

        return await loader.stopsForMap(
            center: center,
            latitudeRadius: latitudeRadius,
            longitudeRadius: longitudeRadius,
            limit: effectiveLimit
        )
    }

    nonisolated func stop(id: String) async -> Stop? {
        await loader.stop(id: id)
    }

    nonisolated func allStops() async -> [Stop] {
        await loader.allStops()
    }

    nonisolated func routesForStop(id: String) async -> [TransitRoute] {
        await loader.routesForStop(id: id)
    }

    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload? {
        await loader.timetableIndex()
    }
}

private actor GTFSDataLoader {
    private let bundle: Bundle
    private let resourceName: String
    private let store: GTFSLocalStore
    private var snapshot: GTFSSnapshot?

    init(
        bundle: Bundle,
        resourceName: String,
        store: GTFSLocalStore,
        initialSnapshot: GTFSSnapshot?
    ) {
        self.bundle = bundle
        self.resourceName = resourceName
        self.store = store
        snapshot = initialSnapshot
    }

    func searchStops(query: String) -> [Stop] {
        currentSnapshot().stopIndex.search(query: query)
    }

    func stopsForMap(
        center: LocationPoint,
        latitudeRadius: Double,
        longitudeRadius: Double,
        limit: Int
    ) -> [Stop] {
        currentSnapshot().stopIndex.stopsForMap(
            center: center,
            latitudeRadius: latitudeRadius,
            longitudeRadius: longitudeRadius,
            limit: limit
        )
    }

    func stop(id: String) -> Stop? {
        currentSnapshot().stopIndex.stop(id: id)
    }

    func allStops() -> [Stop] {
        currentSnapshot().stops
    }

    func routesForStop(id: String) -> [TransitRoute] {
        currentSnapshot().routesByStopId[id, default: []]
    }

    func timetableIndex() -> GTFSTimetableIndexPayload? {
        currentSnapshot().timetable
    }

    func reloadFromDisk() {
        snapshot = loadSnapshotFromDisk()
    }

    private func currentSnapshot() -> GTFSSnapshot {
        if let snapshot {
            return snapshot
        }

        let loaded = loadSnapshotFromDisk()
        snapshot = loaded
        return loaded
    }

    private func loadSnapshotFromDisk() -> GTFSSnapshot {
        let store = Self.loadStopsIndex(store: store)
            ?? Self.loadCompactStore(bundle: bundle, resourceName: resourceName)
        return GTFSSnapshot(
            stops: store?.stops ?? [],
            routesByStopId: store?.routesByStopId ?? [:],
            timetable: Self.loadTimetableIndex(store: self.store)
        )
    }

    private static func loadCompactStore(bundle: Bundle, resourceName: String) -> GTFSCompactStore? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(GTFSCompactPayload.self, from: data)
        else {
            return nil
        }

        let routesById = Dictionary(
            uniqueKeysWithValues: payload.routes.map { route in
                (
                    route.id,
                    TransitRoute(
                        id: route.id,
                        shortName: route.shortName,
                        longName: route.longName.isEmpty ? nil : route.longName,
                        mode: TransportMode(rawValue: route.mode) ?? .unknown,
                        operatorName: route.operatorName.isEmpty ? nil : route.operatorName,
                        dataSource: .gtfs
                    )
                )
            }
        )

        let stops = payload.stops.map { stop in
            Stop(
                id: stop.id,
                name: stop.name,
                locality: stop.locality,
                location: LocationPoint(
                    id: stop.id, name: stop.name, latitude: stop.latitude, longitude: stop.longitude
                ),
                modes: stop.modes.map { TransportMode(rawValue: $0) ?? .unknown },
                dataSource: .gtfs
            )
        }

        let routesByStopId = Dictionary(
            uniqueKeysWithValues: payload.stops.map { stop in
                (
                    stop.id,
                    stop.routeIds.compactMap { routesById[$0] }
                )
            }
        )

        return GTFSCompactStore(stops: stops, routesByStopId: routesByStopId)
    }

    private static func loadStopsIndex(store: GTFSLocalStore) -> GTFSCompactStore? {
        guard FileManager.default.fileExists(atPath: store.stopsIndexURL.path),
              let data = try? Data(contentsOf: store.stopsIndexURL),
              let payload = try? JSONDecoder.gtfsLocal.decode(GTFSStopsIndexPayload.self, from: data)
        else {
            return nil
        }

        let routesById = Dictionary(
            uniqueKeysWithValues: payload.routes.map { route in
                (
                    route.id,
                    TransitRoute(
                        id: route.id,
                        shortName: route.shortName,
                        longName: route.longName,
                        mode: TransportMode(rawValue: route.mode) ?? .unknown,
                        operatorName: route.operatorName,
                        dataSource: .gtfs
                    )
                )
            }
        )

        let stops = payload.stops.map { stop in
            Stop(
                id: stop.id,
                name: stop.name,
                locality: stop.locality,
                location: LocationPoint(
                    id: stop.id,
                    name: stop.name,
                    latitude: stop.latitude,
                    longitude: stop.longitude
                ),
                modes: stop.modes.map { TransportMode(rawValue: $0) ?? .unknown },
                dataSource: .gtfs,
                wheelchairBoarding: WheelchairAccess(gtfsValue: stop.wheelchairBoarding)
            )
        }

        let routesByStopId = Dictionary(
            uniqueKeysWithValues: payload.stops.map { stop in
                (
                    stop.id,
                    stop.routeIds.compactMap { routesById[$0] }
                )
            }
        )

        return GTFSCompactStore(stops: stops, routesByStopId: routesByStopId)
    }

    private static func loadTimetableIndex(store: GTFSLocalStore) -> GTFSTimetableIndexPayload? {
        guard FileManager.default.fileExists(atPath: store.timetableIndexURL.path),
              let data = try? Data(contentsOf: store.timetableIndexURL),
              let payload = try? JSONDecoder.gtfsLocal.decode(
                  GTFSTimetableIndexPayload.self,
                  from: data
              ) else {
            return nil
        }

        return payload
    }
}

private nonisolated struct GTFSSnapshot {
    let stops: [Stop]
    let routesByStopId: [String: [TransitRoute]]
    let timetable: GTFSTimetableIndexPayload?
    let stopIndex: GTFSStopIndex

    init(
        stops: [Stop],
        routesByStopId: [String: [TransitRoute]],
        timetable: GTFSTimetableIndexPayload?
    ) {
        self.stops = stops
        self.routesByStopId = routesByStopId
        self.timetable = timetable
        stopIndex = GTFSStopIndex(stops: stops)
    }
}

private nonisolated struct GTFSCompactStore {
    let stops: [Stop]
    let routesByStopId: [String: [TransitRoute]]
}

private nonisolated struct GTFSStopIndex {
    fileprivate static let bucketSize = 0.02

    private let stopsById: [String: Stop]
    private let searchableStops: [SearchableStop]
    private let buckets: [SpatialBucket: [Stop]]

    init(stops: [Stop]) {
        stopsById = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
        searchableStops = stops
            .map(SearchableStop.init)
            .sorted { lhs, rhs in
                lhs.stop.name.localizedStandardCompare(rhs.stop.name) == .orderedAscending
            }
        buckets = Dictionary(grouping: stops, by: { SpatialBucket(location: $0.location) })
    }

    func stop(id: String) -> Stop? {
        stopsById[id]
    }

    func search(query: String) -> [Stop] {
        searchableStops.compactMap { entry in
            guard entry.name.contains(query) || entry.locality?.contains(query) == true else {
                return nil
            }
            return entry.stop
        }
    }

    func stopsForMap(
        center: LocationPoint,
        latitudeRadius: Double,
        longitudeRadius: Double,
        limit: Int
    ) -> [Stop] {
        let minLatitude = center.latitude - latitudeRadius
        let maxLatitude = center.latitude + latitudeRadius
        let minLongitude = center.longitude - longitudeRadius
        let maxLongitude = center.longitude + longitudeRadius
        let latitudeBuckets = Self.bucketRange(from: minLatitude, to: maxLatitude)
        let longitudeBuckets = Self.bucketRange(from: minLongitude, to: maxLongitude)

        var candidates: [Stop] = []
        candidates.reserveCapacity(min(limit * 2, searchableStops.count))

        for latitudeBucket in latitudeBuckets {
            for longitudeBucket in longitudeBuckets {
                candidates += buckets[SpatialBucket(latitude: latitudeBucket, longitude: longitudeBucket), default: []]
            }
        }

        return candidates.compactMap { stop -> (stop: Stop, distance: Double)? in
            guard abs(stop.location.latitude - center.latitude) <= latitudeRadius,
                  abs(stop.location.longitude - center.longitude) <= longitudeRadius else {
                return nil
            }
            return (stop, Self.squaredDistance(from: stop.location, to: center))
        }
        .sorted {
            if $0.distance != $1.distance {
                return $0.distance < $1.distance
            }
            return $0.stop.name.localizedStandardCompare($1.stop.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.stop)
    }

    private static func bucketRange(from lower: Double, to upper: Double) -> ClosedRange<Int> {
        bucketIndex(for: lower) ... bucketIndex(for: upper)
    }

    private static func bucketIndex(for value: Double) -> Int {
        Int(floor(value / bucketSize))
    }

    private static func squaredDistance(from location: LocationPoint, to center: LocationPoint) -> Double {
        let latitude = location.latitude - center.latitude
        let longitude = location.longitude - center.longitude
        return latitude * latitude + longitude * longitude
    }
}

private nonisolated struct SearchableStop {
    let stop: Stop
    let name: String
    let locality: String?

    init(stop: Stop) {
        self.stop = stop
        name = stop.name.normalizedForSearch
        locality = stop.locality?.normalizedForSearch
    }
}

private nonisolated struct SpatialBucket: Hashable {
    let latitude: Int
    let longitude: Int

    init(latitude: Int, longitude: Int) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(location: LocationPoint) {
        latitude = Int(floor(location.latitude / GTFSStopIndex.bucketSize))
        longitude = Int(floor(location.longitude / GTFSStopIndex.bucketSize))
    }
}

private nonisolated struct GTFSCompactPayload: Decodable {
    let source: String
    let stops: [GTFSCompactStop]
    let routes: [GTFSCompactRoute]
}

private nonisolated struct GTFSCompactStop: Decodable {
    let id: String
    let name: String
    let locality: String?
    let latitude: Double
    let longitude: Double
    let modes: [String]
    let routeIds: [String]
}

private nonisolated struct GTFSCompactRoute: Decodable {
    let id: String
    let shortName: String
    let longName: String
    let mode: String
    let operatorName: String
}

extension String {
    nonisolated var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
