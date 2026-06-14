import Foundation
import Testing

@testable import LuxTransit

struct GTFSIndexBuilderTests {
    @Test func buildsStopsIndexWithRouteMetadata() throws {
        let directory = try makeGTFSFolder()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("stops-index.json")

        try GTFSIndexBuilder().buildStopsIndex(from: directory, to: destination)

        let data = try Data(contentsOf: destination)
        let payload = try JSONDecoder.gtfsLocal.decode(GTFSStopsIndexPayload.self, from: data)
        let lift = try #require(payload.stops.first { $0.id == "S1" })

        #expect(lift.name == "Hill Lift")
        #expect(lift.locality == "Test City")
        #expect(lift.modes.sorted() == ["funicular"])
        #expect(lift.routeIds.sorted() == ["F1"])
        #expect(
            payload.routes.contains {
                $0.id == "F1" && $0.shortName == "F1" && $0.mode == "funicular"
            })
    }

    private func makeGTFSFolder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let files = [
            "stops.txt": """
            stop_id,stop_name,stop_lat,stop_lon,zone_id,location_type
            S1,Hill Lift,49.6289,6.21474,Test City,
            S2,Upper Station,49.61779,6.12589,Test City,0
            """,
            "routes.txt": """
            route_id,agency_id,route_short_name,route_long_name,route_type
            F1,Operator,F1,Lower Station - Upper Station,7
            """,
            "trips.txt": """
            route_id,service_id,trip_id
            F1,WEEK,T-F1
            """,
            "stop_times.txt": """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            T-F1,08:00:00,08:00:00,S1,1
            T-F1,08:10:00,08:10:00,S2,2
            """,
        ]

        for (fileName, content) in files {
            try (content + "\n").write(
                to: directory.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }

        return directory
    }
}
