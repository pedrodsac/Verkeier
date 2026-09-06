import Foundation
import Testing

@testable import Verkeier

struct GTFSFeedSizingTests {
    @Test func indexesShapesFromAnArchiveLargerThanTheFormerSizeLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = [
            "stops.txt": """
            stop_id,stop_name,stop_lat,stop_lon
            A,Start,49.60,6.10
            B,End,49.61,6.11
            """,
            "routes.txt": """
            route_id,route_short_name,route_type
            R,1,3
            """,
            "trips.txt": """
            route_id,service_id,trip_id,shape_id
            R,weekday,T,shape-R
            """,
            "stop_times.txt": """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            T,08:00:00,08:00:00,A,1
            T,08:05:00,08:05:00,B,2
            """,
            "calendar.txt": """
            service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
            weekday,1,1,1,1,1,1,1,20260101,20261231
            """
        ]
        for (name, contents) in files {
            try (contents + "\n").write(
                to: directory.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let shapesURL = directory.appendingPathComponent("shapes.txt")
        try """
        shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence
        shape-R,49.60,6.10,1
        shape-R,49.605,6.105,2
        shape-R,49.61,6.11,3
        """.write(to: shapesURL, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forWritingTo: shapesURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: Character("#").asciiValue!, count: 5_000_001))

        let output = directory.appendingPathComponent("timetable-index.json")
        try GTFSIndexBuilder().buildTimetableIndex(from: directory, to: output)
        let payload = try JSONDecoder.gtfsLocal.decode(
            GTFSTimetableIndexPayload.self,
            from: Data(contentsOf: output)
        )

        #expect(payload.shapes.first?.id == "shape-R")
        #expect(payload.shapes.first?.points.count == 3)
    }
}
