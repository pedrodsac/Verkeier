import Foundation

nonisolated enum TransitIntentHandoff: Codable, Equatable, Sendable {
    case showNearbyStops
    case openFavouriteStop(stopId: String)
    case trackNextDeparture(stopId: String)
    case planRoute(destinationName: String)

    nonisolated private static let defaultsKey = "TransitIntentHandoff"

    nonisolated static func save(_ handoff: TransitIntentHandoff) {
        guard let data = try? JSONEncoder().encode(handoff) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    nonisolated static func consumePending() -> TransitIntentHandoff? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let handoff = try? JSONDecoder().decode(TransitIntentHandoff.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return handoff
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
