import Foundation
import Testing

@testable import LuxTransit

struct GTFSServiceTests {
    @Test func defaultServiceStartsWithoutStopsWhenNoFetchedGTFSExists() {
        let service = LocalGTFSService(bundle: Bundle(), store: isolatedStore())

        #expect(service.searchStops(query: "anything").isEmpty)
    }

    @Test func searchIsAccentTolerantForInjectedStops() {
        let service = LocalGTFSService(
            stops: [makeStop(id: "accented", name: "Café Lift", modes: [.funicular])],
            routesByStopId: [:]
        )

        let results = service.searchStops(query: "cafe")

        #expect(results.map(\.id) == ["accented"])
    }

    @Test func emptySearchReturnsNoStops() {
        let service = LocalGTFSService(stops: [makeStop()], routesByStopId: [:])

        #expect(service.searchStops(query: "   ").isEmpty)
    }

    @Test func routesForStopReturnsGeneratedMetadata() {
        let stop = makeStop(id: "lift", name: "Hill Lift", modes: [.funicular])
        let route = TransitRoute(
            id: "F1",
            shortName: "F1",
            longName: "Lower Station - Upper Station",
            mode: .funicular,
            operatorName: "Operator",
            dataSource: .gtfs
        )
        let service = LocalGTFSService(stops: [stop], routesByStopId: [stop.id: [route]])

        let result = service.searchStops(query: "hill").first

        #expect(result?.id == stop.id)
        #expect(
            result.map { service.routesForStop(id: $0.id).contains { $0.shortName == "F1" } }
                == true)
    }

    @Test func directInjectionStillWorksForFocusedTests() {
        let customStop = makeStop(id: "custom", name: "Custom Stop", modes: [.funicular])
        let service = LocalGTFSService(stops: [customStop], routesByStopId: [:])

        #expect(service.searchStops(query: "custom").map(\.id) == ["custom"])
    }

    @Test func mapStopsAreBoundedSortedAndLimited() {
        let center = LocationPoint(name: "Center", latitude: 49.6, longitude: 6.1)
        let near = makeStop(
            id: "near",
            name: "Near Stop",
            location: LocationPoint(name: "Near Stop", latitude: 49.6005, longitude: 6.1005),
            modes: [.funicular]
        )
        let farther = makeStop(
            id: "farther",
            name: "Farther Stop",
            location: LocationPoint(name: "Farther Stop", latitude: 49.604, longitude: 6.104),
            modes: [.walking]
        )
        let outside = makeStop(
            id: "outside",
            name: "Outside Stop",
            location: LocationPoint(name: "Outside Stop", latitude: 49.7, longitude: 6.2),
            modes: [.unknown]
        )
        let service = LocalGTFSService(stops: [farther, outside, near], routesByStopId: [:])

        let results = service.stopsForMap(
            center: center,
            latitudeDelta: 0.02,
            longitudeDelta: 0.02,
            limit: 2
        )

        #expect(results.map(\.id) == ["near", "farther"])
    }

    @Test func loadsDownloadedIndexWhenAvailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let indexesDirectory = root.appendingPathComponent("indexes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: indexesDirectory, withIntermediateDirectories: true)
        let indexURL = indexesDirectory.appendingPathComponent("stops-index.json")
        let payload = GTFSStopsIndexPayload(
            source: "test",
            stops: [
                GTFSStopsIndexEntry(
                    id: "downloaded-stop",
                    name: "Downloaded Lift",
                    latitude: 49.6,
                    longitude: 6.1,
                    locality: "Test City",
                    modes: ["funicular"],
                    routeIds: ["F1"],
                    parentStation: nil,
                    wheelchairBoarding: nil
                )
            ],
            routes: [
                GTFSRouteIndexEntry(
                    id: "F1",
                    shortName: "F1",
                    longName: "Lower Station - Upper Station",
                    mode: "funicular",
                    operatorName: "Operator"
                )
            ]
        )
        let data = try JSONEncoder.gtfsLocal.encode(payload)
        try data.write(to: indexURL)

        let service = LocalGTFSService(store: GTFSLocalStore(rootDirectory: root))
        let result = service.searchStops(query: "downloaded").first

        #expect(result?.id == "downloaded-stop")
        #expect(result?.modes == [TransportMode.funicular])
        #expect(result.map { service.routesForStop(id: $0.id).first?.shortName } == "F1")
    }

    private func makeStop(
        id: String = "stop",
        name: String = "Stop",
        location: LocationPoint? = nil,
        modes: [TransportMode] = [.unknown]
    ) -> Stop {
        Stop(
            id: id,
            name: name,
            locality: nil,
            location: location ?? LocationPoint(name: name, latitude: 49.6, longitude: 6.1),
            modes: modes,
            dataSource: .gtfs
        )
    }

    private func isolatedStore() -> GTFSLocalStore {
        GTFSLocalStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }
}
