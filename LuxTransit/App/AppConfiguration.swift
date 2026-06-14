import Foundation
import SwiftUI

struct AppConfiguration: Sendable {
    let atpAccessId: String?
    let apiBaseURL: URL
    let avlMessagesURL: URL

    var hasATPAccessId: Bool {
        guard let atpAccessId else { return false }
        return !atpAccessId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let current = AppConfiguration(
        atpAccessId: Bundle.main.object(forInfoDictionaryKey: "ATP_ACCESS_ID") as? String,
        apiBaseURL: URL(string: "https://cdt.hafas.de/opendata/apiserver")!,
        avlMessagesURL: resolvedAVLMessagesURL()
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
}

extension EnvironmentValues {
    @Entry var appConfiguration: AppConfiguration = .current
}
