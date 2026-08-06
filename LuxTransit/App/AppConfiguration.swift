import Foundation
import SwiftUI

nonisolated struct AppConfiguration: Sendable {
    let atpAccessId: String?
    let apiBaseURL: URL
    let avlMessagesURL: URL
    let bikeShareStaticStationsURL: URL
    let bikeShareAPIURL: URL
    let bikeShareAPIKey: String?

    init(
        atpAccessId: String?,
        apiBaseURL: URL,
        avlMessagesURL: URL,
        bikeShareStaticStationsURL: URL = URL(string: "https://developer.jcdecaux.com/rest/vls/stations/luxembourg.csv")!,
        bikeShareAPIURL: URL = URL(string: "https://api.jcdecaux.com/vls/v1/stations")!,
        bikeShareAPIKey: String? = nil
    ) {
        self.atpAccessId = atpAccessId
        self.apiBaseURL = apiBaseURL
        self.avlMessagesURL = avlMessagesURL
        self.bikeShareStaticStationsURL = bikeShareStaticStationsURL
        self.bikeShareAPIURL = bikeShareAPIURL
        self.bikeShareAPIKey = bikeShareAPIKey
    }

    var hasATPAccessId: Bool {
        guard let atpAccessId else { return false }
        return !atpAccessId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let current = AppConfiguration(
        atpAccessId: Bundle.main.object(forInfoDictionaryKey: "ATP_ACCESS_ID") as? String,
        apiBaseURL: URL(string: "https://cdt.hafas.de/opendata/apiserver")!,
        avlMessagesURL: resolvedAVLMessagesURL(),
        bikeShareStaticStationsURL: URL(string: "https://developer.jcdecaux.com/rest/vls/stations/luxembourg.csv")!,
        bikeShareAPIURL: URL(string: "https://api.jcdecaux.com/vls/v1/stations")!,
        bikeShareAPIKey: resolvedBikeShareAPIKey()
    )

    private static func resolvedAVLMessagesURL() -> URL {
        let fallback = URL(string: "https://web.vdl.lu/autobus/data/messages/messages.xml")!
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AVL_MESSAGES_URL") as? String else {
            return fallback
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let url = URL(string: trimmedValue) else {
            return fallback
        }

        return url
    }

    private static func resolvedBikeShareAPIKey() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "JCDECAUX_API_KEY") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension EnvironmentValues {
    @Entry var appConfiguration: AppConfiguration = .current
}
