import Foundation
import SwiftData

enum AppModelContainer {
    static func make() -> ModelContainer {
        let configuration = ModelConfiguration(url: storeURL)

        do {
            return try ModelContainer(for: PersistedFavouriteStop.self, configurations: configuration)
        } catch {
            fatalError("Failed to create SwiftData model container: \(error)")
        }
    }

    private static var storeURL: URL {
        let directory = appGroupApplicationSupportDirectory ?? fallbackApplicationSupportDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to prepare SwiftData directory: \(error)")
        }
        return directory.appendingPathComponent("default.store")
    }

    private static var appGroupApplicationSupportDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedTransitDataStore.appGroupIdentifier)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static var fallbackApplicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Verkéier", isDirectory: true)
    }
}
