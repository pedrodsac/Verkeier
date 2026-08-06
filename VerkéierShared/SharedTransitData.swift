import Foundation

nonisolated enum SharedTransitDataStore {
    static let appGroupIdentifier = "group.dev.pedrocordeiro.LuxTransit"
    static let favouriteStopsKey = "FavouriteStopEntities"
    static let trackedDepartureReminderKey = "TrackedDepartureReminder"

    nonisolated static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    nonisolated static func saveFavouriteStops(_ stops: [SharedFavouriteStop]) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        userDefaults.set(data, forKey: favouriteStopsKey)
        UserDefaults.standard.set(data, forKey: favouriteStopsKey)
    }

    nonisolated static func favouriteStops() -> [SharedFavouriteStop] {
        guard let data = userDefaults.data(forKey: favouriteStopsKey)
                ?? UserDefaults.standard.data(forKey: favouriteStopsKey),
              let stops = try? JSONDecoder().decode([SharedFavouriteStop].self, from: data) else {
            return []
        }

        return stops
    }

    nonisolated static func saveTrackedReminder(_ reminder: SharedTrackedDepartureReminder?) {
        guard let reminder else {
            userDefaults.removeObject(forKey: trackedDepartureReminderKey)
            UserDefaults.standard.removeObject(forKey: trackedDepartureReminderKey)
            return
        }

        guard let data = try? JSONEncoder().encode(reminder) else { return }
        userDefaults.set(data, forKey: trackedDepartureReminderKey)
        UserDefaults.standard.set(data, forKey: trackedDepartureReminderKey)
    }

    nonisolated static func trackedReminder() -> SharedTrackedDepartureReminder? {
        guard let data = userDefaults.data(forKey: trackedDepartureReminderKey)
                ?? UserDefaults.standard.data(forKey: trackedDepartureReminderKey),
              let reminder = try? JSONDecoder().decode(SharedTrackedDepartureReminder.self, from: data) else {
            return nil
        }

        return reminder
    }
}

struct SharedFavouriteStop: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let locality: String?
    let platformIds: [String]

    nonisolated init(id: String, name: String, locality: String?, platformIds: [String]? = nil) {
        self.id = id
        self.name = name.stationDisplayName
        self.locality = locality
        self.platformIds = Self.normalizedPlatformIds(platformIds, fallbackId: id)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case locality
        case platformIds
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)

        self.id = id
        name = try container.decode(String.self, forKey: .name).stationDisplayName
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        platformIds = Self.normalizedPlatformIds(
            try container.decodeIfPresent([String].self, forKey: .platformIds),
            fallbackId: id
        )
    }

    private nonisolated static func normalizedPlatformIds(_ ids: [String]?, fallbackId: String) -> [String] {
        let normalized = (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let unique = normalized.filter { seen.insert($0).inserted }
        return unique.isEmpty ? [fallbackId] : unique
    }
}

struct SharedTrackedDepartureReminder: Codable, Hashable, Sendable {
    let departureId: String
    let stopId: String
    let stopName: String
    let lineName: String
    let destination: String
    let scheduledDeparture: Date?
    let realtimeDeparture: Date?
    let delayMinutes: Int?
    let isCancelled: Bool
    let leadTimeMinutes: Int
    let notifiedDelayMinutes: Int?
    let didNotifyCancellation: Bool
    let lastUpdated: Date

    private enum CodingKeys: String, CodingKey {
        case departureId
        case stopId
        case stopName
        case lineName
        case destination
        case scheduledDeparture
        case realtimeDeparture
        case delayMinutes
        case isCancelled
        case leadTimeMinutes
        case notifiedDelayMinutes
        case didNotifyCancellation
        case lastUpdated
    }

    nonisolated init(
        departureId: String,
        stopId: String,
        stopName: String,
        lineName: String,
        destination: String,
        scheduledDeparture: Date?,
        realtimeDeparture: Date?,
        delayMinutes: Int?,
        isCancelled: Bool,
        leadTimeMinutes: Int,
        notifiedDelayMinutes: Int? = nil,
        didNotifyCancellation: Bool = false,
        lastUpdated: Date
    ) {
        self.departureId = departureId
        self.stopId = stopId
        self.stopName = stopName.stationDisplayName
        self.lineName = lineName
        self.destination = destination
        self.scheduledDeparture = scheduledDeparture
        self.realtimeDeparture = realtimeDeparture
        self.delayMinutes = delayMinutes
        self.isCancelled = isCancelled
        self.leadTimeMinutes = leadTimeMinutes
        self.notifiedDelayMinutes = notifiedDelayMinutes
        self.didNotifyCancellation = didNotifyCancellation
        self.lastUpdated = lastUpdated
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        departureId = try container.decode(String.self, forKey: .departureId)
        stopId = try container.decode(String.self, forKey: .stopId)
        stopName = try container.decode(String.self, forKey: .stopName).stationDisplayName
        lineName = try container.decode(String.self, forKey: .lineName)
        destination = try container.decode(String.self, forKey: .destination)
        scheduledDeparture = try container.decodeIfPresent(Date.self, forKey: .scheduledDeparture)
        realtimeDeparture = try container.decodeIfPresent(Date.self, forKey: .realtimeDeparture)
        delayMinutes = try container.decodeIfPresent(Int.self, forKey: .delayMinutes)
        isCancelled = try container.decode(Bool.self, forKey: .isCancelled)
        leadTimeMinutes = try container.decode(Int.self, forKey: .leadTimeMinutes)
        notifiedDelayMinutes = try container.decodeIfPresent(Int.self, forKey: .notifiedDelayMinutes)
        didNotifyCancellation = try container.decode(Bool.self, forKey: .didNotifyCancellation)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(departureId, forKey: .departureId)
        try container.encode(stopId, forKey: .stopId)
        try container.encode(stopName, forKey: .stopName)
        try container.encode(lineName, forKey: .lineName)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(scheduledDeparture, forKey: .scheduledDeparture)
        try container.encodeIfPresent(realtimeDeparture, forKey: .realtimeDeparture)
        try container.encodeIfPresent(delayMinutes, forKey: .delayMinutes)
        try container.encode(isCancelled, forKey: .isCancelled)
        try container.encode(leadTimeMinutes, forKey: .leadTimeMinutes)
        try container.encodeIfPresent(notifiedDelayMinutes, forKey: .notifiedDelayMinutes)
        try container.encode(didNotifyCancellation, forKey: .didNotifyCancellation)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

nonisolated enum TransitDeepLink: Equatable, Sendable {
    case showNearbyStops
    case openStop(id: String)
    case showDepartures(stopId: String)
    case planRoute(destinationName: String)

    static let scheme = "luxtransit"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        switch url.host() {
        case "nearby":
            self = .showNearbyStops
        case "stop":
            guard let id = Self.queryValue("id", in: url) else { return nil }
            self = .openStop(id: id)
        case "departures":
            guard let id = Self.queryValue("id", in: url) else { return nil }
            self = .showDepartures(stopId: id)
        case "route":
            guard let destination = Self.queryValue("destination", in: url) else { return nil }
            self = .planRoute(destinationName: destination)
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .showNearbyStops:
            components.host = "nearby"
        case .openStop(let id):
            components.host = "stop"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        case .showDepartures(let stopId):
            components.host = "departures"
            components.queryItems = [URLQueryItem(name: "id", value: stopId)]
        case .planRoute(let destinationName):
            components.host = "route"
            components.queryItems = [URLQueryItem(name: "destination", value: destinationName)]
        }

        return components.url ?? URL(string: "\(Self.scheme)://nearby")!
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
