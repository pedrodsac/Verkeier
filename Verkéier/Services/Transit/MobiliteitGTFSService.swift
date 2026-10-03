import Foundation
import MobiliteitKit

/// Owns the installed MobilitéitKit database and the official-feed update
/// policy. Import work stays in the package; this actor selects resources,
/// persists provenance, and maps feed values into the app domain.
actor MobiliteitGTFSService: GTFSService {
    private nonisolated static let datasetURL = URL(string: "https://data.public.lu/api/1/datasets/5a2a58b9111e9b7f34fc6606/")!
    private nonisolated static let refreshInterval: TimeInterval = 24 * 60 * 60
    private nonisolated static let timeZone = TimeZone(identifier: "Europe/Luxembourg")!

    private let directoryURL: URL
    private var databaseURL: URL
    private let metadataURL: URL
    private let session: URLSession
    private var store: GTFSStore?
    private var metadata: GTFSLocalMetadata?
    private var currentStatus: GTFSFeedStatus

    nonisolated static var installedDatabaseURL: URL {
        defaultDirectory().appendingPathComponent("gtfs.sqlite")
    }

    init(session: URLSession = .shared, directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        let metadataURL = base.appendingPathComponent("metadata.json")
        let metadata = Self.loadMetadata(at: metadataURL)
        let databaseURL = base.appendingPathComponent(
            metadata?.databaseFilename ?? Self.legacyDatabaseFilename
        )
        directoryURL = base
        self.databaseURL = databaseURL
        self.metadataURL = metadataURL
        self.session = session
        self.metadata = metadata
        Self.removeInactiveGenerationDatabases(in: base, keeping: databaseURL)
        store = try? GTFSStore(databaseAt: databaseURL)
        Self.debugLog("Initialized. Database present: \(store != nil); metadata: \(metadata?.resourceTitle ?? "none"); valid through: \(metadata?.validThrough ?? "unknown")")
        if let metadata, store != nil, !Self.isExpired(metadata.validThrough) {
            currentStatus = GTFSFeedStatus(
                phase: .ready,
                resourceTitle: metadata.resourceTitle,
                downloadedAt: metadata.downloadedAt,
                lastCheckedAt: metadata.lastCheckedAt,
                releasedAt: metadata.releasedAt,
                validThrough: metadata.validThrough,
                errorMessage: nil
            )
        } else {
            currentStatus = .unavailable
            if let validThrough = metadata?.validThrough, Self.isExpired(validThrough) {
                Self.debugLog("Installed timetable expired on \(validThrough); a current archive is required.")
            }
        }
    }

    nonisolated static func parseResourceDate(_ value: String) -> Date? {
        // data.public.lu emits values such as
        // `2026-09-10T05:19:16.095000+00:00`. ISO8601DateFormatter does not
        // accept fractional seconds unless explicitly configured.
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO.date(from: value) { return date }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value)
    }

    func feedStatus() async -> GTFSFeedStatus { currentStatus }

    /// Returns the current usable generation even while a newer feed is being
    /// checked or downloaded. The existing timetable remains valid for routing
    /// until its last service day has passed.
    func routingDatabaseURL() async -> URL? {
        hasUsableStore ? databaseURL : nil
    }

    func refreshIfNeeded(force: Bool) async -> GTFSFeedStatus {
        Self.debugLog("Refresh requested (force: \(force)). Current phase: \(currentStatus.phase.rawValue).")
        // Route planning and launch preparation can ask for the feed at the
        // same time. Actor methods are re-entrant across network awaits, so a
        // second call must join the active refresh instead of starting another
        // download/import against the same database.
        if currentStatus.phase == .checking || currentStatus.phase == .downloading {
            repeat {
                try? await Task.sleep(for: .milliseconds(100))
            } while currentStatus.phase == .checking || currentStatus.phase == .downloading
            return currentStatus
        }
        if !force,
           store != nil,
           let lastChecked = metadata?.lastCheckedAt,
           Date.now.timeIntervalSince(lastChecked) < Self.refreshInterval,
           !Self.isExpired(metadata?.validThrough) {
            Self.debugLog("Using cached timetable; last checked \(lastChecked.formatted(date: .abbreviated, time: .standard)).")
            return currentStatus
        }

        currentStatus.phase = .checking
        currentStatus.errorMessage = nil
        do {
            Self.debugLog("Fetching the official GTFS catalogue.")
            let remote = try await latestResource()
            Self.debugLog("Selected archive \(remote.title) (resource \(remote.id)); host: \(remote.url.host() ?? "unknown").")
            // `force` bypasses only the once-per-day metadata check. A manual
            // check must not redownload an identical archive.
            let unchanged = store != nil
                && metadata?.resourceID == remote.id
                && (remote.checksum == nil || remote.checksum == metadata?.checksum)
            guard !unchanged else {
                Self.debugLog("Catalogue matches the installed archive; no download required.")
                metadata?.lastCheckedAt = .now
                metadata?.releasedAt = remote.createdAt ?? remote.modifiedAt
                persistMetadata()
                currentStatus.lastCheckedAt = .now
                currentStatus.releasedAt = metadata?.releasedAt
                currentStatus.phase = hasUsableStore ? .ready : .unavailable
                return currentStatus
            }

            currentStatus.phase = .downloading
            let generation = (metadata?.generation ?? 0) + 1
            let installedDatabaseURL = nextGenerationDatabaseURL(generation: generation)
            Self.debugLog("Downloading and importing generation \(generation).")
            let info = try await GTFSArchiveInstaller.downloadAndInstall(
                from: remote.url,
                databaseAt: installedDatabaseURL,
                generation: generation,
                session: session
            )
            let installedStore = try GTFSStore(databaseAt: installedDatabaseURL)
            databaseURL = installedDatabaseURL
            store = installedStore
            metadata = GTFSLocalMetadata(
                resourceID: remote.id,
                resourceTitle: remote.title,
                checksum: remote.checksum,
                downloadedAt: .now,
                lastCheckedAt: .now,
                releasedAt: remote.createdAt ?? remote.modifiedAt,
                generation: info.generation,
                validThrough: info.lastServiceDate.description,
                databaseFilename: installedDatabaseURL.lastPathComponent
            )
            persistMetadata()
            currentStatus = GTFSFeedStatus(
                phase: .ready,
                resourceTitle: remote.title,
                downloadedAt: metadata?.downloadedAt,
                lastCheckedAt: metadata?.lastCheckedAt,
                releasedAt: metadata?.releasedAt,
                validThrough: info.lastServiceDate.description,
                errorMessage: nil
            )
            Self.debugLog("Timetable ready. Service dates: \(info.firstServiceDate) through \(info.lastServiceDate).")
        } catch {
            // Keep any already-open store readable after a metadata, download,
            // or import failure. Never report a valid cached feed as empty.
            metadata?.lastCheckedAt = .now
            persistMetadata()
            currentStatus.phase = hasUsableStore ? .stale : .failed
            currentStatus.lastCheckedAt = .now
            currentStatus.errorMessage = Self.userMessage(for: error)
            Self.debugLog("Refresh failed: \(String(describing: error)). Status: \(currentStatus.phase.rawValue).")
        }
        return currentStatus
    }

    func searchStops(query: String) async -> [Stop] {
        guard let store else { return [] }
        guard let stops = try? await store.searchStops(matching: query, limit: 40) else { return [] }
        return await enrichedStops(stops, store: store)
    }

    func nearbyStops(to location: LocationPoint, radiusMeters: Double, limit: Int) async -> [Stop] {
        guard let store else { return [] }
        guard let stops = try? await store.nearbyStops(
            to: Coordinate(latitude: location.latitude, longitude: location.longitude),
            withinMeters: radiusMeters,
            limit: limit
        ) else { return [] }
        return await enrichedStops(stops, store: store)
    }

    func matchLiveStop(_ liveStop: LiveTransitStop) async -> Stop? {
        guard let store else { return nil }
        guard let candidates = try? await store.nearbyStops(
            to: Coordinate(latitude: liveStop.location.latitude, longitude: liveStop.location.longitude),
            withinMeters: 75,
            limit: 12
        ) else { return nil }
        let matching = candidates.filter {
            $0.name.normalizedForSearch == liveStop.name.normalizedForSearch
        }
        guard matching.count == 1, let staticStop = matching.first else { return nil }
        return Self.stop(
            staticStop,
            routes: [],
            hafasStationIDs: [liveStop.stationID],
            liveModes: liveStop.modes
        )
    }

    func routes(for stop: Stop) async -> [TransitRoute] {
        guard let store, let stopID = stop.gtfsStopID else { return [] }
        guard let routes = try? await store.routes(servingStopIDs: [stopID])[stopID] else { return [] }
        return routes.map { Self.route($0, agency: nil) }
    }

    func scheduledDepartures(for stop: Stop, at date: Date, limit: Int) async -> [OfflineScheduleDeparture] {
        guard let store, let stopID = stop.gtfsStopID else { return [] }
        let feed = await store.feedInfo()
        guard let departures = try? await store.nextScheduledDepartures(
            fromStopID: stopID,
            at: date,
            horizon: 1_439 * 60,
            limit: limit
        ) else { return [] }
        return departures.compactMap { departure in
            let destination = departure.headsign ?? departure.route.longName ?? "Unknown destination"
            // Some feeds publish an arrival/departure time at a trip's final
            // stop even though no onward journey is possible from that stop.
            guard !destination.identifiesSameStation(as: stop.name) else { return nil }
            guard let time = Self.date(for: departure.departure, serviceDay: departure.serviceDay, feed: feed) else { return nil }
            return OfflineScheduleDeparture(
                id: "gtfs:\(departure.tripID):\(departure.stopID):\(departure.departure?.rawValue ?? -1)",
                lineName: departure.route.shortName ?? departure.route.longName ?? "Service",
                destination: destination,
                departureDate: time,
                platform: departure.platformCode,
                mode: Self.mode(routeType: departure.route.type)
            )
        }
    }

    func lineDetail(for route: TransitRoute, directionID: String?, at date: Date) async -> LineDetail? {
        guard let store else { return nil }
        let today = Self.gtfsDate(from: date)
        let feed = await store.feedInfo()
        let todayServiceDay = await store.serviceDay(for: today)
        guard let trips = try? await store.trips(forRouteID: route.id, activeOn: today, limit: 500), !trips.isEmpty else {
            return nil
        }
        let directions = Self.directions(from: trips)
        let selected = directionID ?? directions.first?.id ?? "unknown"
        let selectedDirection = Int(selected)
        guard let representative = trips.first(where: { $0.directionID == selectedDirection }) ?? trips.first,
              let stopTimes = try? await store.stopTimes(forTripID: representative.id) else { return nil }
        let stops = stopTimes.map { time in
            LineStopSequenceEntry(
                id: time.stop.id,
                name: time.stop.name,
                platform: time.stop.platformCode,
                location: LocationPoint(
                    id: time.stop.id,
                    name: time.stop.name,
                    latitude: time.stop.coordinate.latitude,
                    longitude: time.stop.coordinate.longitude,
                    transitStopID: time.stop.id
                )
            )
        }
        var upcoming: [LineTimetableEntry] = []
        if let todayServiceDay {
            for trip in trips where trip.directionID == representative.directionID {
                guard let times = try? await store.stopTimes(forTripID: trip.id),
                      let first = times.first,
                      let departure = Self.date(for: first.departure, serviceDay: todayServiceDay, feed: feed),
                      departure >= date else { continue }
                upcoming.append(LineTimetableEntry(
                    id: trip.id,
                    departureTime: departure,
                    originName: first.stop.name,
                    destinationName: trip.headsign ?? route.longName ?? route.shortName
                ))
            }
        }
        upcoming.sort { $0.departureTime < $1.departureTime }
        let geometry = await routeShape(for: representative.id)
        let overlay = geometry.count >= 2 ? RouteMapOverlay(segments: [
            RouteMapSegment(id: "line:\(route.id):\(selected)", mode: route.mode, routeName: route.shortName, routeId: route.id, coordinates: geometry)
        ]) : nil
        return LineDetail(
            route: route,
            directions: directions,
            selectedDirectionID: selected,
            stopSequence: stops,
            upcomingDepartures: Array(upcoming.prefix(12)),
            serviceSummary: "Static GTFS timetable",
            mapOverlay: overlay
        )
    }

    func routingStops(near location: LocationPoint, radiusMeters: Double, limit: Int) async -> [Stop] {
        await nearbyStops(to: location, radiusMeters: radiusMeters, limit: limit)
    }

    func journeyDepartures(from stop: Stop, after date: Date, horizon: TimeInterval, limit: Int) async -> [GTFSJourneyDeparture] {
        guard let store, let stopID = stop.gtfsStopID,
              let departures = try? await store.nextScheduledDepartures(
                fromStopID: stopID,
                at: date,
                horizon: horizon,
                limit: limit
              ) else { return [] }
        let feed = await store.feedInfo()
        var result: [GTFSJourneyDeparture] = []
        for departure in departures {
            guard let departureDate = Self.date(for: departure.departure, serviceDay: departure.serviceDay, feed: feed) else { continue }
            result.append(GTFSJourneyDeparture(
                tripID: departure.tripID,
                stopID: departure.stopID,
                route: Self.route(departure.route, agency: departure.agency),
                headsign: departure.headsign ?? departure.route.longName ?? departure.route.shortName ?? "Service",
                directionID: departure.directionID,
                departureDate: departureDate,
                arrivalDate: Self.date(for: departure.arrival, serviceDay: departure.serviceDay, feed: feed)
            ))
        }
        return result
    }

    func journeyStops(for tripID: String) async -> [GTFSJourneyStopTime] {
        guard let store, let raw = try? await store.stopTimes(forTripID: tripID),
              let serviceDay = await store.serviceDay(for: Self.gtfsDate(from: .now)) else { return [] }
        let feed = await store.feedInfo()
        return raw.map { value in
            GTFSJourneyStopTime(
                stop: Self.stop(value.stop),
                sequence: value.sequence,
                arrivalDate: Self.date(for: value.arrival, serviceDay: serviceDay, feed: feed),
                departureDate: Self.date(for: value.departure, serviceDay: serviceDay, feed: feed),
                pickupAllowed: value.pickupType != 1,
                dropOffAllowed: value.dropOffType != 1
            )
        }
    }

    func transferRules(from stop: Stop) async -> [GTFSTransferRule] {
        guard let store, let stopID = stop.gtfsStopID,
              let raw = try? await store.transferRules(fromStopID: stopID) else { return [] }
        return raw.map { GTFSTransferRule(destinationStopID: $0.toStopID, minimumTransferSeconds: $0.minimumTransferSeconds) }
    }

    func routeShape(for tripID: String) async -> [RouteMapCoordinate] {
        guard let store, let trip = try? await store.trip(id: tripID), let shapeID = trip.shapeID,
              let shape = try? await store.shape(id: shapeID) else { return [] }
        return shape.coordinates.map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    func routeShapes(for tripIDs: [String]) async -> [String: [RouteMapCoordinate]] {
        guard let store, let shapes = try? await store.shapes(forTripIDs: tripIDs) else { return [:] }
        return shapes.mapValues { coordinates in
            coordinates.map { RouteMapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    nonisolated static func transportMode(forGTFSRouteType routeType: Int) -> TransportMode {
        switch routeType {
        case 0, 5, 900 ... 999:
            .tram
        case 1, 2, 12, 100 ... 199, 300 ... 699:
            .train
        case 3, 11, 200 ... 299, 700 ... 899:
            .bus
        case 7, 1400 ... 1499:
            .funicular
        default:
            .unknown
        }
    }
}

private extension MobiliteitGTFSService {
    struct GTFSLocalMetadata: Codable, Sendable {
        let resourceID: String
        let resourceTitle: String
        let checksum: String?
        let downloadedAt: Date
        var lastCheckedAt: Date
        var releasedAt: Date?
        let generation: Int
        let validThrough: String?
        let databaseFilename: String?
    }

    struct RemoteResource: Sendable {
        let id: String
        let title: String
        let url: URL
        let checksum: String?
        let createdAt: Date?
        let modifiedAt: Date?
    }

    var hasUsableStore: Bool {
        store != nil && !Self.isExpired(metadata?.validThrough)
    }

    nonisolated static let legacyDatabaseFilename = "gtfs.sqlite"

    func nextGenerationDatabaseURL(generation: Int) -> URL {
        directoryURL.appendingPathComponent(
            "gtfs-generation-\(generation)-\(UUID().uuidString).sqlite"
        )
    }

    nonisolated static func removeInactiveGenerationDatabases(
        in directory: URL,
        keeping activeDatabaseURL: URL
    ) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let activePath = activeDatabaseURL.standardizedFileURL.path
        for file in files
        where file.lastPathComponent.hasPrefix("gtfs-generation-")
            && file.pathExtension == "sqlite"
            && file.standardizedFileURL.path != activePath {
            try? manager.removeItem(at: file)
        }
    }

    nonisolated static func isExpired(_ value: String?, at date: Date = .now) -> Bool {
        guard let value else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let finalServiceDay = formatter.date(from: value) else { return false }
        return finalServiceDay < Calendar.current.startOfDay(for: date)
    }

    struct DatasetResponse: Decodable {
        let resources: [DatasetResource]
    }

    struct DatasetResource: Decodable {
        let id: String?
        let title: String?
        let url: URL?
        let latest: URL?
        let format: String?
        let mime: String?
        let filetype: String?
        let checksum: Checksum?
        let createdAt: Date?
        let lastModified: Date?

        enum CodingKeys: String, CodingKey {
            case id, title, url, latest, format, mime, filetype, checksum
            case createdAt = "created_at"
            case lastModified = "last_modified"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decodeIfPresent(String.self, forKey: .id)
            title = try values.decodeIfPresent(String.self, forKey: .title)
            url = try values.decodeURL(forKey: .url)
            latest = try values.decodeURL(forKey: .latest)
            format = try values.decodeIfPresent(String.self, forKey: .format)
            mime = try values.decodeIfPresent(String.self, forKey: .mime)
            filetype = try values.decodeIfPresent(String.self, forKey: .filetype)
            checksum = try values.decodeIfPresent(Checksum.self, forKey: .checksum)
            createdAt = try values.decodeDate(forKey: .createdAt)
            lastModified = try values.decodeDate(forKey: .lastModified)
        }
    }

    struct Checksum: Decodable { let value: String? }

    func latestResource() async throws -> RemoteResource {
        let (data, response) = try await session.data(from: Self.datasetURL)
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let dataset = try JSONDecoder().decode(DatasetResponse.self, from: data)
        let values = dataset.resources.compactMap { resource -> RemoteResource? in
            let title = resource.title ?? "GTFS archive"
            let candidate = resource.latest ?? resource.url
            guard let id = resource.id, let url = candidate else { return nil }
            let type = [title, resource.format, resource.filetype, resource.mime].compactMap { $0 }.joined(separator: " ").lowercased()
            guard type.contains("gtfs"), type.contains("zip") else { return nil }
            return RemoteResource(id: id, title: title, url: url, checksum: resource.checksum?.value, createdAt: resource.createdAt, modifiedAt: resource.lastModified)
        }
        guard let latest = values.max(by: { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }) else {
            throw URLError(.fileDoesNotExist)
        }
        return latest
    }

    nonisolated static func defaultDirectory() -> URL {
        let manager = FileManager.default
        let root = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.temporaryDirectory
        let directory = root.appendingPathComponent("Mobiliteit", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }


    nonisolated static func loadMetadata(at url: URL) -> GTFSLocalMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GTFSLocalMetadata.self, from: data)
    }

    func persistMetadata() {
        guard let metadata, let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    nonisolated static func userMessage(for error: Error) -> String {
        if error is URLError { return "The GTFS update could not be downloaded." }
        if error is GTFSArchiveError { return "The downloaded GTFS feed could not be installed." }
        return "The GTFS update could not be completed."
    }

    nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print("[Verkéier GTFS] \(Date.now.formatted(date: .omitted, time: .standard)): \(message)")
        #else
        _ = message
        #endif
    }

    func enrichedStops(
        _ stops: [MobiliteitKit.TransitStop],
        store: GTFSStore
    ) async -> [Stop] {
        let routesByStopID = (try? await store.routes(servingStopIDs: stops.map(\.id))) ?? [:]
        return stops.map { stop in
            Self.stop(stop, routes: routesByStopID[stop.id] ?? [])
        }
    }

    nonisolated static func stop(
        _ source: MobiliteitKit.TransitStop,
        routes: [MobiliteitKit.TransitRoute] = [],
        hafasStationIDs: [String] = [],
        liveModes: [TransportMode] = []
    ) -> Stop {
        var seenModes: Set<TransportMode> = []
        let scheduledModes = routes
            .map { transportMode(forGTFSRouteType: $0.type) }
            .filter { $0 != .unknown && seenModes.insert($0).inserted }
        return Stop(
            id: source.id,
            name: source.name,
            location: LocationPoint(
                id: source.id,
                name: source.name,
                latitude: source.coordinate.latitude,
                longitude: source.coordinate.longitude,
                transitStopID: source.id
            ),
            modes: liveModes.isEmpty ? scheduledModes : liveModes,
            dataSource: .gtfs,
            platformIds: source.platformCode.map { [$0] },
            gtfsStopID: source.id,
            hafasStationIDs: hafasStationIDs
        )
    }

    nonisolated static func route(_ source: MobiliteitKit.TransitRoute, agency: Agency?) -> TransitRoute {
        TransitRoute(
            id: source.id,
            shortName: source.shortName ?? source.longName ?? "Service",
            longName: source.longName,
            mode: mode(routeType: source.type),
            operatorName: agency?.name,
            dataSource: .gtfs
        )
    }

    nonisolated static func mode(routeType: Int) -> TransportMode {
        transportMode(forGTFSRouteType: routeType)
    }

    nonisolated static func gtfsDate(from date: Date) -> GTFSDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return try! GTFSDate(year: values.year!, month: values.month!, day: values.day!)
    }

    nonisolated static func date(for time: ServiceTime?, serviceDay: ServiceDay, feed: FeedInfo) -> Date? {
        guard let time else { return nil }
        // GTFSStore already returns service-day values. Luxembourg's GTFS feed
        // uses Europe/Luxembourg, so deliberately preserve 24:00+ service time.
        let day = feed.firstServiceDate.adding(days: Int(serviceDay.index))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let midnight = calendar.date(from: components) else { return nil }
        return midnight.addingTimeInterval(TimeInterval(time.rawValue))
    }

    nonisolated static func directions(from trips: [MobiliteitKit.TransitTrip]) -> [LineDetailDirection] {
        var seen: Set<String> = []
        return trips.compactMap { trip in
            let id = String(trip.directionID ?? 0)
            guard seen.insert(id).inserted else { return nil }
            return LineDetailDirection(id: id, title: trip.headsign ?? "Direction \(Int(id) ?? 0)", subtitle: nil)
        }
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeURL(forKey key: Key) throws -> URL? {
        if let url = try? decode(URL.self, forKey: key) { return url }
        return try decodeIfPresent(String.self, forKey: key).flatMap(URL.init(string:))
    }

    nonisolated func decodeDate(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return MobiliteitGTFSService.parseResourceDate(value)
    }
}
