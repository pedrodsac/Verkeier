import Foundation
import Testing
@testable import Verkeier

struct JCDecauxBikeShareStoreTests {
    @Test func liveFeedBootstrapsStationsWhenStaticDownloadFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BikeShareFeedFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cacheURL = directory.appendingPathComponent("stations.json")
        let appConfiguration = AppConfiguration(apiProxyURL: URL(string: "https://bike-fixture.invalid")!,
            avlMessagesURL: URL(string: "https://fixture.invalid")!,
            bikeShareStaticStationsURL: URL(string: "https://bike-fixture.invalid/static.csv")!)
        let store = JCDecauxBikeShareStore(configuration: appConfiguration, session: session, cacheURL: cacheURL)
        await store.refreshAvailability()
        let stations = await store.stations()
        #expect(stations.count == 1)
        let station = try #require(stations.first)
        #expect(station.id == "1")
        #expect(station.location.latitude == 49.61)
        #expect(station.bikesAvailable == 7)
        #expect(station.docksAvailable == 3)
        #expect(station.isOpen == true)
        let reloaded = JCDecauxBikeShareStore(configuration: appConfiguration, session: session, cacheURL: cacheURL)
        #expect(await reloaded.stations() == stations)
    }

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

private nonisolated final class BikeShareFeedFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "bike-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isStatic = request.url?.path == "/static.csv"
        let response = HTTPURLResponse(url: request.url!, statusCode: isStatic ? 503 : 200,
            httpVersion: nil, headerFields: nil)!
        let body = """
        [{"number":1,"name":"Central","position":{"lat":49.61,"lng":6.13},
          "bike_stands":10,"available_bikes":7,"available_bike_stands":3,"status":"OPEN","last_update":1800000000000}]
        """
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((isStatic ? "unavailable" : body).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
