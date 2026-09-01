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
    /// Shared by route-service values that are recreated by SwiftUI.
    let routeSearchContextCache = RouteSearchContextCache()

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
        let routeSearchContextCache = self.routeSearchContextCache
        updateTask = Task { [loader, routeSearchContextCache] in
            for await _ in NotificationCenter.default.notifications(named: .gtfsDidUpdate) {
                await loader.reloadFromDisk()
                await routeSearchContextCache.removeAll()
            }
        }
    }

    deinit {
        updateTask.cancel()
    }

    nonisolated func searchStops(query: String) async -> [Stop] {
        let normalizedQuery = query.normalizedForStopSearch
        guard !normalizedQuery.isEmpty else { return [] }

        // Capture the immutable index from the actor, then score it on a
        // concurrent executor. Even broad fuzzy matching therefore cannot run
        // on the UI actor while the user is typing.
        let stopIndex = await loader.stopIndex()
        return await withTaskGroup(of: [Stop].self, returning: [Stop].self) { group in
            group.addTask(priority: .userInitiated) {
                stopIndex.search(query: normalizedQuery)
            }
            return await group.next() ?? []
        }
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

    func stopIndex() -> GTFSStopIndex {
        currentSnapshot().stopIndex
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
        var matches: [StopSearchMatch] = []
        matches.reserveCapacity(min(searchableStops.count, StopSearchConfiguration.resultLimit * 2))

        for (index, entry) in searchableStops.enumerated() {
            // A cancelled query should release its worker promptly instead of
            // competing with the newer, debounced query.
            if index.isMultiple(of: 32), Task.isCancelled {
                return []
            }

            if let match = entry.match(for: query) {
                matches.append(match)
            }
        }

        guard !Task.isCancelled else { return [] }

        return matches
            .sorted(by: StopSearchMatch.isOrderedBefore)
            .prefix(StopSearchConfiguration.resultLimit)
            .map(\.stop)
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
    let fullName: String
    let tokens: [String]

    init(stop: Stop) {
        self.stop = stop
        fullName = stop.fullName.normalizedForStopSearch
        tokens = fullName.split(separator: " ").map(String.init)
    }

    func match(for query: String) -> StopSearchMatch? {
        if fullName == query {
            return StopSearchMatch(stop: stop, tier: .exact, score: 1)
        }

        let queryTokens = query.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return nil }

        if allQueryTokensMatch(queryTokens, using: { token, queryToken in token.hasPrefix(queryToken) }) {
            return StopSearchMatch(stop: stop, tier: .prefix, score: 1)
        }

        // One- and two-character searches deliberately stay prefix-only to
        // avoid broad, low-signal result lists while typing.
        guard query.count > 2 else { return nil }

        if fullName.contains(query) || allQueryTokensMatch(queryTokens, using: { token, queryToken in
            token.contains(queryToken)
        }) {
            return StopSearchMatch(stop: stop, tier: .substring, score: 1)
        }

        let phraseSimilarity = StopSearchMatch.similarity(between: query, and: fullName)
        let tokenSimilarities = queryTokens.map { queryToken in
            tokens.map { StopSearchMatch.similarity(between: queryToken, and: $0) }.max() ?? 0
        }
        let tokenThresholdsMet = zip(queryTokens, tokenSimilarities).allSatisfy { queryToken, similarity in
            similarity >= StopSearchMatch.minimumSimilarity(forTokenLength: queryToken.count)
        }

        guard tokenThresholdsMet || phraseSimilarity >= 0.60 else { return nil }

        let averageTokenSimilarity = tokenSimilarities.reduce(0, +) / Double(tokenSimilarities.count)
        return StopSearchMatch(
            stop: stop,
            tier: .fuzzy,
            score: max(phraseSimilarity, averageTokenSimilarity)
        )
    }

    private func allQueryTokensMatch(
        _ queryTokens: [String],
        using predicate: (String, String) -> Bool
    ) -> Bool {
        queryTokens.allSatisfy { queryToken in
            tokens.contains { predicate($0, queryToken) }
        }
    }
}

private nonisolated struct StopSearchMatch {
    enum Tier: Int {
        case exact
        case prefix
        case substring
        case fuzzy
    }

    let stop: Stop
    let tier: Tier
    let score: Double

    static func isOrderedBefore(_ lhs: StopSearchMatch, _ rhs: StopSearchMatch) -> Bool {
        if lhs.tier != rhs.tier {
            return lhs.tier.rawValue < rhs.tier.rawValue
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let nameOrder = lhs.stop.name.localizedStandardCompare(rhs.stop.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.stop.id < rhs.stop.id
    }

    static func minimumSimilarity(forTokenLength length: Int) -> Double {
        switch length {
        case 0...2: 1
        case 3...4: 0.66
        case 5...7: 0.60
        default: 0.55
        }
    }

    /// Damerau-Levenshtein similarity using optimal string alignment. It
    /// tolerates adjacent transpositions while remaining cheap for stop names.
    static func similarity(between lhs: String, and rhs: String) -> Double {
        let source = Array(lhs)
        let target = Array(rhs)
        let maximumLength = max(source.count, target.count)
        guard maximumLength > 0 else { return 1 }

        var twoRowsBack = Array(0...target.count)
        var previousRow = twoRowsBack

        for sourceIndex in 1...source.count {
            var currentRow = Array(repeating: 0, count: target.count + 1)
            currentRow[0] = sourceIndex

            for targetIndex in 1...target.count {
                let substitutionCost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1
                var distance = min(
                    previousRow[targetIndex] + 1,
                    currentRow[targetIndex - 1] + 1,
                    previousRow[targetIndex - 1] + substitutionCost
                )

                if sourceIndex > 1,
                   targetIndex > 1,
                   source[sourceIndex - 1] == target[targetIndex - 2],
                   source[sourceIndex - 2] == target[targetIndex - 1] {
                    distance = min(distance, twoRowsBack[targetIndex - 2] + 1)
                }

                currentRow[targetIndex] = distance
            }

            twoRowsBack = previousRow
            previousRow = currentRow
        }

        return 1 - Double(previousRow[target.count]) / Double(maximumLength)
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

    /// Normalization used only by GTFS stop matching. Punctuation acts as a
    /// separator so "Gare-Centrale" and "Gare Centrale" produce the same
    /// searchable tokens, while existing general-purpose normalization keeps
    /// its current semantics.
    nonisolated var normalizedForStopSearch: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let punctuationSeparated = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }.joined()
        return punctuationSeparated
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
