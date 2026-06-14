import Foundation

final class LocalGTFSService: GTFSService, @unchecked Sendable {
    private let lock = NSLock()
    private let bundle: Bundle
    private let resourceName: String
    private let store: GTFSLocalStore
    private var stops: [Stop]
    private var routesByStopId: [String: [TransitRoute]]
    private var updateObserver: NSObjectProtocol?

    init(
        bundle: Bundle = .main,
        resourceName: String = "gtfs-compact",
        store: GTFSLocalStore = GTFSLocalStore(),
        stops: [Stop]? = nil,
        routesByStopId: [String: [TransitRoute]]? = nil
    ) {
        self.bundle = bundle
        self.resourceName = resourceName
        self.store = store

        if let stops, let routesByStopId {
            self.stops = stops
            self.routesByStopId = routesByStopId
        } else if let store = Self.loadStopsIndex(store: store) {
            self.stops = store.stops
            self.routesByStopId = store.routesByStopId
        } else if let store = Self.loadCompactStore(bundle: bundle, resourceName: resourceName) {
            self.stops = store.stops
            self.routesByStopId = store.routesByStopId
        } else {
            self.stops = []
            self.routesByStopId = [:]
        }

        updateObserver = NotificationCenter.default.addObserver(
            forName: .gtfsDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadFromDisk()
        }
    }

    deinit {
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }

    func searchStops(query: String) -> [Stop] {
        let normalizedQuery = query.normalizedForSearch
        guard !normalizedQuery.isEmpty else { return [] }

        let currentStops = locked { stops }
        return
            currentStops
            .filter { stop in
                stop.name.normalizedForSearch.contains(normalizedQuery)
                    || (stop.locality?.normalizedForSearch.contains(normalizedQuery) ?? false)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func stopsForMap(
        center: LocationPoint,
        latitudeDelta: Double,
        longitudeDelta: Double,
        limit: Int
    ) -> [Stop] {
        let effectiveLimit = max(0, limit)
        guard effectiveLimit > 0 else { return [] }

        let currentStops = locked { stops }
        let latitudeRadius = max(latitudeDelta / 2, 0.01)
        let longitudeRadius = max(longitudeDelta / 2, 0.01)

        return currentStops.compactMap { stop -> (stop: Stop, distance: Double)? in
            guard abs(stop.location.latitude - center.latitude) <= latitudeRadius,
                abs(stop.location.longitude - center.longitude) <= longitudeRadius
            else {
                return nil
            }

            return (stop, squaredDistance(from: stop.location, to: center))
        }
        .sorted { $0.distance < $1.distance }
        .prefix(effectiveLimit)
        .map(\.stop)
    }

    func stop(id: String) -> Stop? {
        locked { stops.first { $0.id == id } }
    }

    func routesForStop(id: String) -> [TransitRoute] {
        locked { routesByStopId[id, default: []] }
    }

    private func squaredDistance(from location: LocationPoint, to center: LocationPoint) -> Double {
        let latitude = location.latitude - center.latitude
        let longitude = location.longitude - center.longitude
        return latitude * latitude + longitude * longitude
    }

    private func reloadFromDisk() {
        guard
            let store = Self.loadStopsIndex(store: store)
                ?? Self.loadCompactStore(bundle: bundle, resourceName: resourceName)
        else {
            return
        }

        locked {
            stops = store.stops
            routesByStopId = store.routesByStopId
        }
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    private static func loadCompactStore(bundle: Bundle, resourceName: String) -> GTFSCompactStore?
    {
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
            })

        let stops = payload.stops.map { stop in
            Stop(
                id: stop.id,
                name: stop.name,
                locality: stop.locality,
                location: LocationPoint(
                    name: stop.name, latitude: stop.latitude, longitude: stop.longitude),
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
            })

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
            })

        let stops = payload.stops.map { stop in
            Stop(
                id: stop.id,
                name: stop.name,
                locality: stop.locality,
                location: LocationPoint(
                    name: stop.name,
                    latitude: stop.latitude,
                    longitude: stop.longitude
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
            })

        return GTFSCompactStore(stops: stops, routesByStopId: routesByStopId)
    }
}

private struct GTFSCompactStore {
    let stops: [Stop]
    let routesByStopId: [String: [TransitRoute]]
}

private struct GTFSCompactPayload: Decodable {
    let source: String
    let stops: [GTFSCompactStop]
    let routes: [GTFSCompactRoute]
}

private struct GTFSCompactStop: Decodable {
    let id: String
    let name: String
    let locality: String?
    let latitude: Double
    let longitude: Double
    let modes: [String]
    let routeIds: [String]
}

private struct GTFSCompactRoute: Decodable {
    let id: String
    let shortName: String
    let longName: String
    let mode: String
    let operatorName: String
}

extension String {
    var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
