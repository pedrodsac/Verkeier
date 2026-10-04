import Foundation

/// The live vel’OH! station feed. Static station identities are refreshed once
/// per app launch; dynamic counts are refreshed when a route is calculated or
/// explicitly refreshed by the user.
struct JCDecauxBikeShareService: BikeShareService {
    private let store: JCDecauxBikeShareStore

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        store = JCDecauxBikeShareStore(configuration: configuration, session: session)
    }

    func bikeShareStations(near location: LocationPoint) async -> [BikeShareStation] {
        let stations = await store.stations()
        return stations.sorted {
            routeSearchDistanceMeters(from: $0.location, to: location)
                < routeSearchDistanceMeters(from: $1.location, to: location)
        }
    }

    func refreshStaticStations() async {
        await store.refreshStaticStations()
    }

    func refreshAvailability() async {
        await store.refreshAvailability()
    }

    func snapshot() async -> BikeShareSnapshot? {
        await store.snapshot()
    }
}

actor JCDecauxBikeShareStore {
    private struct DynamicStation: Decodable {
        let number: Int
        let name: String
        let position: Position
        let bikeStands: Int?
        let availableBikeStands: Int?
        let availableBikes: Int?
        let status: String?
        let lastUpdate: Int64?

        struct Position: Decodable {
            let lat: Double
            let lng: Double
        }
    }

    private let configuration: AppConfiguration
    private let session: URLSession
    private var staticStations: [BikeShareStation] = []
    private var currentSnapshot: BikeShareSnapshot?
    private var didLoadCachedSnapshot = false
    private let cacheURL: URL

    init(configuration: AppConfiguration, session: URLSession, cacheURL: URL? = nil) {
        self.configuration = configuration
        self.session = session
        self.cacheURL = cacheURL ?? Self.defaultCacheURL
    }

    private func loadCachedSnapshotIfNeeded() {
        guard !didLoadCachedSnapshot else { return }
        didLoadCachedSnapshot = true
        if let cached = Self.readCachedSnapshot(at: cacheURL) {
            staticStations = cached.stations.map { station in
                BikeShareStation(
                    id: station.id,
                    name: station.name,
                    location: station.location,
                    capacity: station.capacity,
                    isOpen: station.isOpen
                )
            }
            currentSnapshot = cached
        }
    }

    func stations() -> [BikeShareStation] {
        loadCachedSnapshotIfNeeded()
        return currentSnapshot?.stations ?? staticStations
    }

    func snapshot() -> BikeShareSnapshot? {
        loadCachedSnapshotIfNeeded()
        return currentSnapshot
    }

    func refreshStaticStations() async {
        loadCachedSnapshotIfNeeded()
        do {
            let (data, response) = try await session.data(from: configuration.bikeShareStaticStationsURL)
            try Self.validate(response: response, data: data)
            let parsed = try Self.parseCSV(data)
            guard !parsed.isEmpty else { throw BikeShareFeedError.emptyStaticFeed }

            staticStations = parsed
            if let currentSnapshot {
                let dynamicByID = Dictionary(uniqueKeysWithValues: currentSnapshot.stations.map { ($0.id, $0) })
                let merged = parsed.map { station -> BikeShareStation in
                    guard let dynamic = dynamicByID[station.id] else { return station }
                    return Self.merge(static: station, dynamic: dynamic)
                }
                self.currentSnapshot = BikeShareSnapshot(stations: merged, fetchedAt: currentSnapshot.fetchedAt)
            }
            Self.writeCachedSnapshot(BikeShareSnapshot(stations: parsed, fetchedAt: .now), to: cacheURL)
        } catch {
            // The last valid snapshot remains available for offline startup.
        }
    }

    func refreshAvailability() async {
        loadCachedSnapshotIfNeeded()
        if staticStations.isEmpty {
            await refreshStaticStations()
        }

        do {
            let url: URL
            if configuration.hasAPIProxyURL, let apiProxyURL = configuration.apiProxyURL {
                url = apiProxyURL.appending(path: "bike-share/stations")
            } else if let key = configuration.bikeShareAPIKey {
                var components = URLComponents(url: configuration.bikeShareAPIURL, resolvingAgainstBaseURL: false)
                components?.queryItems = [
                    URLQueryItem(name: "contract", value: "luxembourg"),
                    URLQueryItem(name: "apiKey", value: key)
                ]
                guard let directURL = components?.url else { return }
                url = directURL
            } else {
                return
            }

            let (data, response) = try await session.data(from: url)
            try Self.validate(response: response, data: data)
            // JCDecaux's dynamic endpoint uses snake_case keys
            // (available_bikes, available_bike_stands, last_update).
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let dynamic = try decoder.decode([DynamicStation].self, from: data)
            let dynamicByID = Dictionary(uniqueKeysWithValues: dynamic.map { (String($0.number), $0) })
            let merged = staticStations.map { station -> BikeShareStation in
                guard let live = dynamicByID[station.id] else { return station }
                return BikeShareStation(
                    id: station.id,
                    name: live.name.isEmpty ? station.name : live.name,
                    location: station.location,
                    bikesAvailable: live.availableBikes,
                    docksAvailable: live.availableBikeStands,
                    capacity: live.bikeStands ?? station.capacity,
                    isOpen: live.status.map { $0.uppercased() == "OPEN" },
                    lastUpdated: live.lastUpdate.map { Date(timeIntervalSince1970: Double($0) / 1000) }
                )
            }
            currentSnapshot = BikeShareSnapshot(stations: merged, fetchedAt: .now)
        } catch {
            // Routes remain usable with static or last-known availability.
        }
    }

    private static func merge(static station: BikeShareStation, dynamic: BikeShareStation) -> BikeShareStation {
        BikeShareStation(
            id: station.id,
            name: station.name,
            location: station.location,
            bikesAvailable: dynamic.bikesAvailable,
            docksAvailable: dynamic.docksAvailable,
            capacity: dynamic.capacity ?? station.capacity,
            isOpen: dynamic.isOpen,
            lastUpdated: dynamic.lastUpdated
        )
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BikeShareFeedError.invalidResponse
        }
        guard !data.isEmpty else { throw BikeShareFeedError.emptyStaticFeed }
    }

    private static func parseCSV(_ data: Data) throws -> [BikeShareStation] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw BikeShareFeedError.invalidEncoding
        }
        let rows = string.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = rows.first.map(parseCSVRow),
              header.map({ $0.lowercased() }) == ["number", "name", "address", "latitude", "longitude"] else {
            throw BikeShareFeedError.invalidHeader
        }

        var result: [BikeShareStation] = []
        var ids = Set<String>()
        for row in rows.dropFirst() {
            let fields = parseCSVRow(row)
            guard fields.count >= 5,
                  let latitude = Double(fields[3]),
                  let longitude = Double(fields[4]),
                  (-90 ... 90).contains(latitude),
                  (-180 ... 180).contains(longitude) else {
                continue
            }
            let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, ids.insert(id).inserted else { continue }
            result.append(BikeShareStation(
                id: id,
                name: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                location: LocationPoint(id: "veloh-\(id)", name: fields[1], latitude: latitude, longitude: longitude)
            ))
        }
        return result
    }

    private static func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var field = ""
        var quoted = false
        var index = row.startIndex
        while index < row.endIndex {
            let character = row[index]
            if character == "\"" {
                if quoted, row.index(after: index) < row.endIndex,
                   row[row.index(after: index)] == "\"" {
                    field.append("\"")
                    index = row.index(after: index)
                } else {
                    quoted.toggle()
                }
            } else if character == "," && !quoted {
                result.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = row.index(after: index)
        }
        result.append(field)
        return result
    }

    private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("veloh-stations.json")
    }

    private static func readCachedSnapshot(at cacheURL: URL) -> BikeShareSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(BikeShareSnapshot.self, from: data)
    }

    private static func writeCachedSnapshot(_ snapshot: BikeShareSnapshot, to cacheURL: URL) {
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

private enum BikeShareFeedError: Error {
    case invalidResponse
    case emptyStaticFeed
    case invalidEncoding
    case invalidHeader
}
