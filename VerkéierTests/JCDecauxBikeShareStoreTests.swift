import Foundation
import Testing
@testable import Verkeier

struct JCDecauxBikeShareStoreTests {
    @Test func firstActorAccessLoadsCacheWrittenAfterConstruction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("stations.json")
        let store = JCDecauxBikeShareStore(
            configuration: AppConfiguration(avlMessagesURL: URL(string: "https://fixture.invalid")!),
            session: .shared, cacheURL: cacheURL
        )
        let station = BikeShareStation(
            id: "fixture", name: "Central", location: LocationPoint(latitude: 49.61, longitude: 6.13),
            bikesAvailable: 7, docksAvailable: 3, capacity: 10, isOpen: true
        )
        let cached = BikeShareSnapshot(stations: [station], fetchedAt: Date(timeIntervalSince1970: 100))
        try JSONEncoder().encode(cached).write(to: cacheURL)
        #expect(await store.stations() == [station])
        #expect(await store.snapshot() == cached)
    }
}
