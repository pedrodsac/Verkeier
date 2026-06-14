import Foundation

nonisolated enum SharedTransitDataStore {
    static let appGroupIdentifier = "group.dev.pedrocordeiro.LuxTransit"
    static let favouriteStopsKey = "FavouriteStopEntities"

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
}

struct SharedFavouriteStop: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let locality: String?
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
