import Foundation

nonisolated struct GTFSValidator: Sendable {
    private let requiredFiles = [
        "agency.txt",
        "stops.txt",
        "routes.txt",
        "trips.txt",
        "stop_times.txt"
    ]

    private let requiredStopColumns = [
        "stop_id",
        "stop_name",
        "stop_lat",
        "stop_lon"
    ]

    func validatedFeedDirectory(in directory: URL) throws -> URL {
        if isValid(directory) {
            return directory
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in children where isDirectory(child) && isValid(child) {
            return child
        }

        try validate(directory)
        return directory
    }

    func validate(_ directory: URL) throws {
        let fileManager = FileManager.default
        for fileName in requiredFiles {
            let url = directory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                throw GTFSUpdateError.validationFailed("Missing \(fileName).")
            }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw GTFSUpdateError.validationFailed("\(fileName) is empty.")
            }
        }

        let calendar = directory.appendingPathComponent("calendar.txt")
        let calendarDates = directory.appendingPathComponent("calendar_dates.txt")
        guard nonEmptyFileExists(calendar) || nonEmptyFileExists(calendarDates) else {
            throw GTFSUpdateError.validationFailed("Missing calendar.txt or calendar_dates.txt.")
        }

        try validateStopsHeader(directory.appendingPathComponent("stops.txt"))
    }

    private func isValid(_ directory: URL) -> Bool {
        (try? validate(directory)) != nil
    }

    private func validateStopsHeader(_ stopsURL: URL) throws {
        guard let header = try String(contentsOf: stopsURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .first else {
            throw GTFSUpdateError.validationFailed("stops.txt is empty.")
        }

        let columns = Set(CSVRowParser.parse(String(header)).map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = requiredStopColumns.filter { !columns.contains($0) }
        guard missing.isEmpty else {
            throw GTFSUpdateError.validationFailed("stops.txt is missing \(missing.joined(separator: ", ")).")
        }
    }

    private func nonEmptyFileExists(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
