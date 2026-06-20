import Foundation

struct TransitIntentHandoffStore {
    nonisolated(unsafe) let defaults: UserDefaults

    nonisolated static let shared = TransitIntentHandoffStore(
        defaults: UserDefaults(suiteName: SharedTransitDataStore.appGroupIdentifier) ?? .standard
    )

    nonisolated func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    nonisolated func consume<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: key)
        return value
    }
}

nonisolated enum TransitIntentHandoff: Codable, Equatable, Sendable {
    case showNearbyStops
    case openFavouriteStop(stopId: String)
    case trackNextDeparture(stopId: String)
    case planRoute(destinationName: String)

    nonisolated private static let defaultsKey = "TransitIntentHandoff"

    nonisolated static func save(
        _ handoff: TransitIntentHandoff,
        store: TransitIntentHandoffStore = .shared
    ) {
        store.save(handoff, forKey: defaultsKey)
    }

    nonisolated static func consumePending(
        from store: TransitIntentHandoffStore = .shared
    ) -> TransitIntentHandoff? {
        store.consume(TransitIntentHandoff.self, forKey: defaultsKey)
    }

    nonisolated init?(_ deepLink: TransitDeepLink) {
        switch deepLink {
        case .showNearbyStops:
            self = .showNearbyStops
        case .openStop(let id):
            self = .openFavouriteStop(stopId: id)
        case .showDepartures(let stopId):
            self = .trackNextDeparture(stopId: stopId)
        case .planRoute(let destinationName):
            self = .planRoute(destinationName: destinationName)
        }
    }
}
