import Foundation
import Testing

@testable import LuxTransit

struct GTFSServiceTests {
    @Test func defaultServiceStartsWithoutStopsWhenNoFetchedGTFSExists() async {
        let service = LocalGTFSService(bundle: Bundle(), store: isolatedStore())

        #expect(await service.searchStops(query: "anything").isEmpty)
    }

    @Test func searchIsAccentTolerantForInjectedStops() async {
        let service = LocalGTFSService(
            stops: [makeStop(id: "accented", name: "Café Lift", modes: [.funicular])],
            routesByStopId: [:]
        )

        let results = await service.searchStops(query: "cafe")

        #expect(results.map(\.id) == ["accented"])
    }

    @Test func emptySearchReturnsNoStops() async {
        let service = LocalGTFSService(stops: [makeStop()], routesByStopId: [:])

        #expect(await service.searchStops(query: "   ").isEmpty)
    }

    @Test func routesForStopReturnsGeneratedMetadata() async {
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

        let result = await service.searchStops(query: "hill").first

        #expect(result?.id == stop.id)
        if let result {
            #expect(await service.routesForStop(id: result.id).contains { $0.shortName == "F1" })
        }
    }

    @Test func directInjectionStillWorksForFocusedTests() async {
        let customStop = makeStop(id: "custom", name: "Custom Stop", modes: [.funicular])
        let service = LocalGTFSService(stops: [customStop], routesByStopId: [:])

        #expect(await service.searchStops(query: "custom").map(\.id) == ["custom"])
    }

    @Test func mapStopsAreBoundedSortedAndLimited() async {
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

        let results = await service.stopsForMap(
            center: center,
            latitudeDelta: 0.02,
            longitudeDelta: 0.02,
            limit: 2
        )

        #expect(results.map(\.id) == ["near", "farther"])
    }

    @Test func concurrentSearchAndMapLookupsUseConsistentSnapshot() async {
        let center = LocationPoint(name: "Center", latitude: 49.6, longitude: 6.1)
        let stops = (0..<24).map { index in
            makeStop(
                id: "stop-\(index)",
                name: "Concurrent Stop \(index)",
                location: LocationPoint(
                    name: "Concurrent Stop \(index)",
                    latitude: 49.6 + Double(index) * 0.0001,
                    longitude: 6.1 + Double(index) * 0.0001
                ),
                modes: [.bus]
            )
        }
        let service = LocalGTFSService(stops: stops, routesByStopId: [:])

        let resultCounts = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await service.searchStops(query: "concurrent").count
                }
                group.addTask {
                    await service.stopsForMap(
                        center: center,
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02,
                        limit: 24
                    ).count
                }
            }

            var counts: [Int] = []
            for await count in group {
                counts.append(count)
            }
            return counts
        }

        #expect(resultCounts.allSatisfy { $0 == 24 })
    }

    @Test func loadsDownloadedIndexWhenAvailable() async throws {
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
        let result = await service.searchStops(query: "downloaded").first

        #expect(result?.id == "downloaded-stop")
        #expect(result?.modes == [TransportMode.funicular])
        if let result {
            #expect(await service.routesForStop(id: result.id).first?.shortName == "F1")
        }
    }

    @Test func gtfsUpdateReloadsSearchLookupAndSpatialIndex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GTFSLocalStore(rootDirectory: root)
        try FileManager.default.createDirectory(
            at: store.indexesDirectory,
            withIntermediateDirectories: true
        )
        try writeStopsIndex(
            stops: [
                GTFSStopsIndexEntry(
                    id: "old",
                    name: "Old Stop",
                    latitude: 49.6,
                    longitude: 6.1,
                    locality: nil,
                    modes: ["bus"],
                    routeIds: [],
                    parentStation: nil,
                    wheelchairBoarding: nil
                )
            ],
            to: store.stopsIndexURL
        )
        let service = LocalGTFSService(store: store)

        try writeStopsIndex(
            stops: [
                GTFSStopsIndexEntry(
                    id: "new",
                    name: "New Stop",
                    latitude: 49.6005,
                    longitude: 6.1005,
                    locality: nil,
                    modes: ["tram"],
                    routeIds: [],
                    parentStation: nil,
                    wheelchairBoarding: nil
                )
            ],
            to: store.stopsIndexURL
        )
        NotificationCenter.default.post(name: .gtfsDidUpdate, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        let mapResults = await service.stopsForMap(
            center: LocationPoint(name: "Center", latitude: 49.6, longitude: 6.1),
            latitudeDelta: 0.02,
            longitudeDelta: 0.02,
            limit: 10
        )
        #expect(await service.searchStops(query: "new").map(\.id) == ["new"])
        #expect(await service.searchStops(query: "old").isEmpty)
        #expect(mapResults.map(\.id) == ["new"])
    }

    @Test func loadsDownloadedTimetableIndexWhenAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GTFSLocalStore(rootDirectory: root)
        try FileManager.default.createDirectory(
            at: store.indexesDirectory,
            withIntermediateDirectories: true
        )
        let payload = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1",
                    name: "Hill Lift",
                    latitude: 49.6,
                    longitude: 6.1,
                    parentStation: nil,
                    platformCode: nil
                )
            ],
            routes: [],
            services: [],
            trips: [],
            transfers: [],
            shapes: []
        )
        let data = try JSONEncoder.gtfsLocal.encode(payload)
        try data.write(to: store.timetableIndexURL)

        let service = LocalGTFSService(store: store)

        #expect(await service.timetableIndex()?.stops.first?.id == "S1")
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

    private func writeStopsIndex(stops: [GTFSStopsIndexEntry], to url: URL) throws {
        let payload = GTFSStopsIndexPayload(source: "test", stops: stops, routes: [])
        let data = try JSONEncoder.gtfsLocal.encode(payload)
        try data.write(to: url, options: [.atomic])
    }
}
