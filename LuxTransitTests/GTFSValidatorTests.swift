import Foundation
import Testing
@testable import LuxTransit

struct GTFSValidatorTests {
    @Test func acceptsMinimalValidGTFSFolder() throws {
        let directory = try makeGTFSFolder()

        try GTFSValidator().validate(directory)
    }

    @Test func rejectsMissingStopsFile() throws {
        let directory = try makeGTFSFolder(omitting: ["stops.txt"])

        #expect(throws: GTFSUpdateError.self) {
            try GTFSValidator().validate(directory)
        }
    }

    @Test func rejectsEmptyRequiredFile() throws {
        let directory = try makeGTFSFolder(emptyFiles: ["routes.txt"])

        #expect(throws: GTFSUpdateError.self) {
            try GTFSValidator().validate(directory)
        }
    }

    @Test func rejectsStopsFileMissingRequiredColumns() throws {
        let directory = try makeGTFSFolder(stopsHeader: "stop_id,stop_name,stop_lat")

        #expect(throws: GTFSUpdateError.self) {
            try GTFSValidator().validate(directory)
        }
    }

    private func makeGTFSFolder(
        omitting omittedFiles: Set<String> = [],
        emptyFiles: Set<String> = [],
        stopsHeader: String = "stop_id,stop_name,stop_lat,stop_lon"
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let contents: [String: String] = [
            "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\n1,ATP,https://mobiliteit.lu,Europe/Luxembourg\n",
            "stops.txt": "\(stopsHeader)\n1,Theatre,49.61,6.13\n",
            "routes.txt": "route_id,route_short_name,route_type\n1,T1,0\n",
            "trips.txt": "route_id,service_id,trip_id\n1,weekday,trip-1\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\ntrip-1,08:00:00,08:00:00,1,1\n",
            "calendar_dates.txt": "service_id,date,exception_type\nweekday,20260614,1\n"
        ]

        for (fileName, content) in contents where !omittedFiles.contains(fileName) {
            let url = directory.appendingPathComponent(fileName)
            try (emptyFiles.contains(fileName) ? "" : content).write(to: url, atomically: true, encoding: .utf8)
        }

        return directory
    }
}
