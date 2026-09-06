import Foundation
import Testing

@testable import Verkeier

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
        #expect(lift.wheelchairBoarding == "0")
        #expect(lift.modes.sorted() == ["funicular"])
        #expect(lift.routeIds.sorted() == ["F1"])
        #expect(
            payload.routes.contains {
                $0.id == "F1" && $0.shortName == "F1" && $0.mode == "funicular"
            })
    }

    @Test func buildsTimetableIndexWithTripsCalendarsTransfersAndShapes() throws {
        let directory = try makeGTFSFolder()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timetable-index.json")

        try GTFSIndexBuilder().buildTimetableIndex(from: directory, to: destination)

        let data = try Data(contentsOf: destination)
        let payload = try JSONDecoder.gtfsLocal.decode(GTFSTimetableIndexPayload.self, from: data)
        let trip = try #require(payload.trips.first { $0.id == "T-F1" })
        let service = try #require(payload.services.first { $0.id == "WEEK" })
        let shape = try #require(payload.shapes.first { $0.id == "shape-f1" })

        #expect(payload.stops.map(\.id).sorted() == ["S1", "S2"])
        let platformStop = try #require(payload.stops.first { $0.id == "S2" })
        #expect(platformStop.parentStation == "P1")
        #expect(platformStop.platformCode == "5")
        #expect(payload.routes.map(\.id) == ["F1"])
        #expect(trip.stopTimes.map(\.departureSeconds) == [28_800, 87_000])
        #expect(trip.stopTimes.compactMap(\.shapeDistanceTraveled) == [0, 1.4])
        #expect(service.addedDates.contains("20260614"))
        #expect(payload.transfers.first?.minimumTransferSeconds == 180)
        #expect(shape.points.count == 2)
    }

    private func makeGTFSFolder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let files = [
            "agency.txt": """
            agency_name,agency_url,agency_timezone
            Test Transit,https://example.com,Europe/Luxembourg
            """,
            "stops.txt": """
            stop_id,stop_name,stop_lat,stop_lon,zone_id,location_type,parent_station,platform_code,wheelchair_boarding
            S1,Hill Lift,49.6289,6.21474,Test City,,,,0
            S2,Upper Station,49.61779,6.12589,Test City,0,P1,5,1
            """,
            "routes.txt": """
            route_id,agency_id,route_short_name,route_long_name,route_type
            F1,Operator,F1,Lower Station - Upper Station,7
            """,
            "trips.txt": """
            route_id,service_id,trip_id,shape_id
            F1,WEEK,T-F1,shape-f1
            """,
            "stop_times.txt": """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence,shape_dist_traveled
            T-F1,08:00:00,08:00:00,S1,1,0
            T-F1,24:10:00,24:10:00,S2,2,1.4
            """,
            "calendar_dates.txt": """
            service_id,date,exception_type
            WEEK,20260614,1
            """,
            "transfers.txt": """
            from_stop_id,to_stop_id,transfer_type,min_transfer_time
            S1,S2,2,180
            """,
            "shapes.txt": """
            shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled
            shape-f1,49.6289,6.21474,1,0
            shape-f1,49.61779,6.12589,2,1.4
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
