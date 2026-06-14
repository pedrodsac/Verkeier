import Foundation

nonisolated struct GTFSIndexBuilder: Sendable {
    func buildStopsIndex(from feedDirectory: URL, to destination: URL) throws {
        let routesById = try readRoutes(from: feedDirectory)
        let tripRouteIds = try readTripRouteIds(from: feedDirectory)
        let routeIdsByStopId = try readRouteIdsByStopId(
            from: feedDirectory,
            tripRouteIds: tripRouteIds
        )
        let stopsTable = try readCSV(feedDirectory.appendingPathComponent("stops.txt"))
        let indexByHeader = stopsTable.indexByHeader
        let required = ["stop_id", "stop_name", "stop_lat", "stop_lon"]
        guard required.allSatisfy({ indexByHeader[$0] != nil }) else {
            throw GTFSUpdateError.validationFailed("stops.txt is missing required columns.")
        }

        let stops = stopsTable.rows.compactMap { line -> GTFSStopsIndexEntry? in
            let values = CSVRowParser.parse(line)
            guard let id = values.value(for: "stop_id", in: indexByHeader), !id.isEmpty,
                  let name = values.value(for: "stop_name", in: indexByHeader), !name.isEmpty,
                  let latitudeText = values.value(for: "stop_lat", in: indexByHeader),
                  let longitudeText = values.value(for: "stop_lon", in: indexByHeader),
                  let latitude = Double(latitudeText),
                  let longitude = Double(longitudeText) else {
                return nil
            }

            let routeIds = Array(routeIdsByStopId[id, default: []]).sorted()
            let modes = Array(Set(routeIds.compactMap { routesById[$0]?.mode })).sorted()
            return GTFSStopsIndexEntry(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                locality: values.value(for: "zone_id", in: indexByHeader),
                modes: modes,
                routeIds: routeIds,
                parentStation: values.value(for: "parent_station", in: indexByHeader),
                wheelchairBoarding: values.value(for: "wheelchair_boarding", in: indexByHeader)
            )
        }

        let routeIdsUsed = Set(stops.flatMap(\.routeIds))
        let routes = routesById
            .filter { routeIdsUsed.contains($0.key) }
            .map(\.value)
            .sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
        let payload = GTFSStopsIndexPayload(source: "data.public.lu GTFS", stops: stops, routes: routes)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dataOut = try JSONEncoder.gtfsLocal.encode(payload)
        try dataOut.write(to: destination, options: [.atomic])
    }

    private func readRoutes(from feedDirectory: URL) throws -> [String: GTFSRouteIndexEntry] {
        let table = try readCSV(feedDirectory.appendingPathComponent("routes.txt"))
        return Dictionary(uniqueKeysWithValues: table.rows.compactMap { line in
            let values = CSVRowParser.parse(line)
            guard let id = values.value(for: "route_id", in: table.indexByHeader), !id.isEmpty else {
                return nil
            }
            let route = GTFSRouteIndexEntry(
                id: id,
                shortName: values.value(for: "route_short_name", in: table.indexByHeader)
                    ?? values.value(for: "route_long_name", in: table.indexByHeader)
                    ?? id,
                longName: values.value(for: "route_long_name", in: table.indexByHeader),
                mode: mode(for: values.value(for: "route_type", in: table.indexByHeader)),
                operatorName: values.value(for: "agency_id", in: table.indexByHeader)
            )
            return (id, route)
        })
    }

    private func readTripRouteIds(from feedDirectory: URL) throws -> [String: String] {
        let table = try readCSV(feedDirectory.appendingPathComponent("trips.txt"))
        return Dictionary(uniqueKeysWithValues: table.rows.compactMap { line in
            let values = CSVRowParser.parse(line)
            guard let tripId = values.value(for: "trip_id", in: table.indexByHeader), !tripId.isEmpty,
                  let routeId = values.value(for: "route_id", in: table.indexByHeader), !routeId.isEmpty else {
                return nil
            }
            return (tripId, routeId)
        })
    }

    private func readRouteIdsByStopId(
        from feedDirectory: URL,
        tripRouteIds: [String: String]
    ) throws -> [String: Set<String>] {
        let table = try readCSV(feedDirectory.appendingPathComponent("stop_times.txt"))
        return table.rows.reduce(into: [:]) { result, line in
            let values = CSVRowParser.parse(line)
            guard let stopId = values.value(for: "stop_id", in: table.indexByHeader), !stopId.isEmpty,
                  let tripId = values.value(for: "trip_id", in: table.indexByHeader),
                  let routeId = tripRouteIds[tripId] else {
                return
            }
            result[stopId, default: []].insert(routeId)
        }
    }

    private func readCSV(_ url: URL) throws -> CSVTable {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw GTFSUpdateError.validationFailed("\(url.lastPathComponent) is not UTF-8.")
        }

        var lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else {
            throw GTFSUpdateError.validationFailed("\(url.lastPathComponent) is empty.")
        }

        let headers = CSVRowParser.parse(lines.removeFirst())
        let indexByHeader = Dictionary(
            uniqueKeysWithValues: headers.enumerated().map { ($0.element, $0.offset) }
        )
        return CSVTable(headers: headers, indexByHeader: indexByHeader, rows: lines)
    }

    private func mode(for routeType: String?) -> String {
        switch routeType {
        case "0": "tram"
        case "1": "unknown"
        case "2": "train"
        case "3": "bus"
        case "7": "funicular"
        default: "unknown"
        }
    }
}

nonisolated struct GTFSStopsIndexPayload: Codable, Sendable {
    let source: String
    let stops: [GTFSStopsIndexEntry]
    var routes: [GTFSRouteIndexEntry] = []
}

nonisolated struct GTFSStopsIndexEntry: Codable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    var locality: String?
    var modes: [String] = []
    var routeIds: [String] = []
    let parentStation: String?
    let wheelchairBoarding: String?
}

nonisolated struct GTFSRouteIndexEntry: Codable, Sendable {
    let id: String
    let shortName: String
    let longName: String?
    let mode: String
    let operatorName: String?
}

private struct CSVTable {
    let headers: [String]
    let indexByHeader: [String: Int]
    let rows: [String]
}

nonisolated enum CSVRowParser {
    static func parse(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isQuoted = false
                        if next == "," {
                            fields.append(current)
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == "," && !isQuoted {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        fields.append(current)
        return fields
    }
}

private extension Array where Element == String {
    nonisolated func value(for header: String, in indexByHeader: [String: Int]) -> String? {
        guard let index = indexByHeader[header], indices.contains(index) else { return nil }
        return self[index]
    }
}
