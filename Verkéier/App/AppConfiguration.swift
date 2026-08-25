import Foundation
import SwiftUI

nonisolated struct AppConfiguration: Sendable {
    let atpAccessId: String?
    let apiBaseURL: URL
    let apiProxyURL: URL?
    let avlMessagesURL: URL
    let bikeShareStaticStationsURL: URL
    let bikeShareAPIURL: URL
    let bikeShareAPIKey: String?

    init(
        atpAccessId: String?,
        apiBaseURL: URL,
        avlMessagesURL: URL,
        apiProxyURL: URL? = nil,
        bikeShareStaticStationsURL: URL = URL(string: "https://developer.jcdecaux.com/rest/vls/stations/luxembourg.csv")!,
        bikeShareAPIURL: URL = URL(string: "https://api.jcdecaux.com/vls/v1/stations")!,
        bikeShareAPIKey: String? = nil
    ) {
        self.atpAccessId = atpAccessId
        self.apiBaseURL = apiBaseURL
        self.apiProxyURL = apiProxyURL
        self.avlMessagesURL = avlMessagesURL
        self.bikeShareStaticStationsURL = bikeShareStaticStationsURL
        self.bikeShareAPIURL = bikeShareAPIURL
        self.bikeShareAPIKey = bikeShareAPIKey
    }

    var hasATPAccessId: Bool {
        if hasAPIProxyURL { return true }
        guard let atpAccessId else { return false }
        return !atpAccessId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAPIProxyURL: Bool {
        guard let apiProxyURL else { return false }
        return apiProxyURL.scheme == "https" || apiProxyURL.scheme == "http"
    }

    static let current = AppConfiguration(
        atpAccessId: nil,
        apiBaseURL: URL(string: "https://cdt.hafas.de/opendata/apiserver")!,
        avlMessagesURL: resolvedAVLMessagesURL(),
        apiProxyURL: resolvedAPIProxyURL(),
        bikeShareStaticStationsURL: URL(string: "https://developer.jcdecaux.com/rest/vls/stations/luxembourg.csv")!,
        bikeShareAPIURL: URL(string: "https://api.jcdecaux.com/vls/v1/stations")!
    )

    private static func resolvedAPIProxyURL() -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "API_PROXY_URL") as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let url = URL(string: trimmedValue),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }

        return url
    }

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

}

extension EnvironmentValues {
    @Entry var appConfiguration: AppConfiguration = .current
}
