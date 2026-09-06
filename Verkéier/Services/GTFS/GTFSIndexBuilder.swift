import Foundation
import Transit

nonisolated struct GTFSIndexBuilder: Sendable {
    func buildStopsIndex(from feedDirectory: URL, to destination: URL) throws {
        let routesById = try readRoutes(from: feedDirectory)
        let tripRouteIds = try readTripRouteIds(from: feedDirectory)
        let routeIdsByStopId = try readRouteIdsByStopId(
            from: feedDirectory,
            tripRouteIds: tripRouteIds
        )
        let wheelchairBoardingByStopId = try readWheelchairBoardingByStopId(from: feedDirectory)

        let stops = try readStops(from: feedDirectory).compactMap { stop -> GTFSStopsIndexEntry? in
            guard !stop.stopID.isEmpty,
                  let name = stop.name, !name.isEmpty,
                  let latitude = stop.latitude,
                  let longitude = stop.longitude else {
                return nil
            }

            let routeIds = Array(routeIdsByStopId[stop.stopID, default: []]).sorted()
            let modes = Array(Set(routeIds.compactMap { routesById[$0]?.mode })).sorted()
            return GTFSStopsIndexEntry(
                id: stop.stopID,
                name: name,
                latitude: latitude,
                longitude: longitude,
                locality: stop.zoneID,
                modes: modes,
                routeIds: routeIds,
                parentStation: stop.parentStationID,
                wheelchairBoarding: wheelchairBoarding(for: stop)
                    ?? wheelchairBoardingByStopId[stop.stopID]
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

    func buildTimetableIndex(from feedDirectory: URL, to destination: URL) throws {
        let routesById = try readRoutes(from: feedDirectory)
        let stopsById = try readTimetableStops(from: feedDirectory)
        let services = try readServices(from: feedDirectory)
        let trips = try readTimetableTrips(from: feedDirectory)
        let transfers = try readTransfers(from: feedDirectory)
        let usedShapeIDs = Set(trips.compactMap(\.shapeId).filter { !$0.isEmpty })
        let shapes = try readShapes(from: feedDirectory, including: usedShapeIDs)

        let usedRouteIds = Set(trips.map(\.routeId))
        let routes = routesById.values
            .filter { usedRouteIds.contains($0.id) }
            .map {
                GTFSTimetableRouteEntry(
                    id: $0.id,
                    shortName: $0.shortName,
                    longName: $0.longName,
                    mode: $0.mode,
                    operatorName: $0.operatorName
                )
            }
            .sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }

        let usedStopIds = Set(trips.flatMap { $0.stopTimes.map(\.stopId) })
        let stops = stopsById.values
            .filter { usedStopIds.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let payload = GTFSTimetableIndexPayload(
            revision: UUID().uuidString,
            source: "data.public.lu GTFS",
            stops: stops,
            routes: routes,
            services: services.sorted { $0.id < $1.id },
            trips: trips.sorted { $0.id < $1.id },
            transfers: transfers,
            // `shape_id` on a trip is the link between its timetable and the
            // geometry published in shapes.txt. Retain that geometry even for
            // a large feed: otherwise MapKit can only draw straight lines
            // between stops, which is inaccurate for almost every route.
            shapes: shapes.sorted { $0.id < $1.id }
        )

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dataOut = try JSONEncoder.gtfsLocal.encode(payload)
        try dataOut.write(to: destination, options: [.atomic])
    }

    private func readRoutes(from feedDirectory: URL) throws -> [String: GTFSRouteIndexEntry] {
        let feed = Transit.Feed(contentsOfURL: feedDirectory)
        guard let routes = feed.routes?.routes else {
            throw GTFSUpdateError.validationFailed("Transit could not read routes.txt.")
        }

        return Dictionary(uniqueKeysWithValues: routes.compactMap { route in
            guard !route.routeID.isEmpty else {
                return nil
            }
            let route = GTFSRouteIndexEntry(
                id: route.routeID,
                shortName: route.shortName ?? route.name ?? route.routeID,
                longName: route.name,
                mode: mode(for: route.type),
                operatorName: route.agencyID
            )
            return (route.id, route)
        })
    }

    private func readStops(from feedDirectory: URL) throws -> [Transit.Stop] {
        let feed = Transit.Feed(contentsOfURL: feedDirectory)
        guard let stops = feed.stops?.stops else {
            throw GTFSUpdateError.validationFailed("Transit could not read stops.txt.")
        }
        return stops
    }

    /// Transit currently exposes, but does not populate, stop accessibility.
    /// Preserve the optional GTFS field until that upstream support is available.
    private func readWheelchairBoardingByStopId(from feedDirectory: URL) throws -> [String: String] {
        let table = try readCSV(feedDirectory.appendingPathComponent("stops.txt"))
        guard table.indexByHeader["wheelchair_boarding"] != nil else { return [:] }

        return table.rows.reduce(into: [:]) { result, line in
            let values = CSVRowParser.parse(line)
            guard let stopID = values.value(for: "stop_id", in: table.indexByHeader),
                  !stopID.isEmpty,
                  let wheelchairBoarding = values.value(
                      for: "wheelchair_boarding",
                      in: table.indexByHeader
                  ),
                  !wheelchairBoarding.isEmpty else {
                return
            }
            result[stopID] = wheelchairBoarding
        }
    }

    private func wheelchairBoarding(for stop: Transit.Stop) -> String? {
        switch stop.accessibility {
        case .some(.unknownOrInherits): "0"
        case .some(.partialOrFull): "1"
        case .some(.none): "2"
        case nil: nil
        }
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

    private func readTimetableStops(from feedDirectory: URL) throws -> [String: GTFSTimetableStopEntry] {
        let table = try readCSV(feedDirectory.appendingPathComponent("stops.txt"))
        return Dictionary(uniqueKeysWithValues: table.rows.compactMap { line in
            let values = CSVRowParser.parse(line)
            guard let id = values.value(for: "stop_id", in: table.indexByHeader), !id.isEmpty,
                  let name = values.value(for: "stop_name", in: table.indexByHeader), !name.isEmpty,
                  let latitudeText = values.value(for: "stop_lat", in: table.indexByHeader),
                  let longitudeText = values.value(for: "stop_lon", in: table.indexByHeader),
                  let latitude = Double(latitudeText),
                  let longitude = Double(longitudeText) else {
                return nil
            }

            return (
                id,
                GTFSTimetableStopEntry(
                    id: id,
                    name: name,
                    latitude: latitude,
                    longitude: longitude,
                    parentStation: values.value(for: "parent_station", in: table.indexByHeader),
                    platformCode: values.value(for: "platform_code", in: table.indexByHeader)
                )
            )
        })
    }

    private func readServices(from feedDirectory: URL) throws -> [GTFSTimetableServiceEntry] {
        var servicesById: [String: GTFSTimetableServiceEntry] = [:]

        if let calendarTable = try readCSVIfExists(feedDirectory.appendingPathComponent("calendar.txt")) {
            for line in calendarTable.rows {
                let values = CSVRowParser.parse(line)
                guard let id = values.value(for: "service_id", in: calendarTable.indexByHeader),
                      !id.isEmpty else {
                    continue
                }

                servicesById[id] = GTFSTimetableServiceEntry(
                    id: id,
                    weekdays: weekdaySet(from: values, in: calendarTable.indexByHeader),
                    startDate: values.value(for: "start_date", in: calendarTable.indexByHeader),
                    endDate: values.value(for: "end_date", in: calendarTable.indexByHeader),
                    addedDates: [],
                    removedDates: []
                )
            }
        }

        if let datesTable = try readCSVIfExists(feedDirectory.appendingPathComponent("calendar_dates.txt")) {
            for line in datesTable.rows {
                let values = CSVRowParser.parse(line)
                guard let id = values.value(for: "service_id", in: datesTable.indexByHeader),
                      !id.isEmpty,
                      let date = values.value(for: "date", in: datesTable.indexByHeader),
                      !date.isEmpty,
                      let exceptionType = values.value(for: "exception_type", in: datesTable.indexByHeader)
                else {
                    continue
                }

                let existing = servicesById[id] ?? GTFSTimetableServiceEntry(
                    id: id,
                    weekdays: [],
                    startDate: nil,
                    endDate: nil,
                    addedDates: [],
                    removedDates: []
                )

                if exceptionType == "1" {
                    servicesById[id] = GTFSTimetableServiceEntry(
                        id: existing.id,
                        weekdays: existing.weekdays,
                        startDate: existing.startDate,
                        endDate: existing.endDate,
                        addedDates: existing.addedDates.union([date]),
                        removedDates: existing.removedDates
                    )
                } else if exceptionType == "2" {
                    servicesById[id] = GTFSTimetableServiceEntry(
                        id: existing.id,
                        weekdays: existing.weekdays,
                        startDate: existing.startDate,
                        endDate: existing.endDate,
                        addedDates: existing.addedDates,
                        removedDates: existing.removedDates.union([date])
                    )
                }
            }
        }

        return Array(servicesById.values)
    }

    private func readTimetableTrips(from feedDirectory: URL) throws -> [GTFSTimetableTripEntry] {
        let tripsTable = try readCSV(feedDirectory.appendingPathComponent("trips.txt"))
        var tripsById: [String: PartialTrip] = [:]

        for line in tripsTable.rows {
            let values = CSVRowParser.parse(line)
            guard let id = values.value(for: "trip_id", in: tripsTable.indexByHeader), !id.isEmpty,
                  let routeId = values.value(for: "route_id", in: tripsTable.indexByHeader),
                  !routeId.isEmpty,
                  let serviceId = values.value(for: "service_id", in: tripsTable.indexByHeader),
                  !serviceId.isEmpty else {
                continue
            }

            tripsById[id] = PartialTrip(
                id: id,
                routeId: routeId,
                serviceId: serviceId,
                headsign: values.value(for: "trip_headsign", in: tripsTable.indexByHeader),
                directionId: values.value(for: "direction_id", in: tripsTable.indexByHeader),
                shapeId: values.value(for: "shape_id", in: tripsTable.indexByHeader)
            )
        }

        let stopTimesTable = try readCSV(feedDirectory.appendingPathComponent("stop_times.txt"))
        var stopTimesByTripId: [String: [GTFSTimetableStopTimeEntry]] = [:]

        for line in stopTimesTable.rows {
            let values = CSVRowParser.parse(line)
            guard let tripId = values.value(for: "trip_id", in: stopTimesTable.indexByHeader),
                  !tripId.isEmpty,
                  let stopId = values.value(for: "stop_id", in: stopTimesTable.indexByHeader),
                  !stopId.isEmpty,
                  let sequenceText = values.value(for: "stop_sequence", in: stopTimesTable.indexByHeader),
                  let sequence = Int(sequenceText),
                  let arrivalText = values.value(for: "arrival_time", in: stopTimesTable.indexByHeader),
                  let departureText = values.value(for: "departure_time", in: stopTimesTable.indexByHeader),
                  let arrivalSeconds = seconds(fromGTFSClock: arrivalText),
                  let departureSeconds = seconds(fromGTFSClock: departureText) else {
                continue
            }

            stopTimesByTripId[tripId, default: []].append(
                GTFSTimetableStopTimeEntry(
                    stopId: stopId,
                    arrivalSeconds: arrivalSeconds,
                    departureSeconds: departureSeconds,
                    sequence: sequence,
                    headsign: values.value(for: "stop_headsign", in: stopTimesTable.indexByHeader),
                    pickupType: values.value(for: "pickup_type", in: stopTimesTable.indexByHeader),
                    dropOffType: values.value(for: "drop_off_type", in: stopTimesTable.indexByHeader),
                    shapeDistanceTraveled: Double(
                        values.value(for: "shape_dist_traveled", in: stopTimesTable.indexByHeader)
                            ?? ""
                    )
                )
            )
        }

        return tripsById.values.compactMap { trip in
            let stopTimes = (stopTimesByTripId[trip.id] ?? [])
                .sorted { $0.sequence < $1.sequence }
            guard stopTimes.count >= 2 else { return nil }

            return GTFSTimetableTripEntry(
                id: trip.id,
                routeId: trip.routeId,
                serviceId: trip.serviceId,
                headsign: trip.headsign,
                directionId: trip.directionId,
                shapeId: trip.shapeId,
                stopTimes: stopTimes
            )
        }
    }

    private func readTransfers(from feedDirectory: URL) throws -> [GTFSTimetableTransferEntry] {
        guard let table = try readCSVIfExists(feedDirectory.appendingPathComponent("transfers.txt")) else {
            return []
        }

        return table.rows.compactMap { line in
            let values = CSVRowParser.parse(line)
            guard let fromStopId = values.value(for: "from_stop_id", in: table.indexByHeader),
                  !fromStopId.isEmpty,
                  let toStopId = values.value(for: "to_stop_id", in: table.indexByHeader),
                  !toStopId.isEmpty else {
                return nil
            }

            return GTFSTimetableTransferEntry(
                fromStopId: fromStopId,
                toStopId: toStopId,
                minimumTransferSeconds: Int(
                    values.value(for: "min_transfer_time", in: table.indexByHeader) ?? ""
                ),
                transferType: Int(values.value(for: "transfer_type", in: table.indexByHeader) ?? "0"),
                fromRouteID: values.value(for: "from_route_id", in: table.indexByHeader),
                toRouteID: values.value(for: "to_route_id", in: table.indexByHeader),
                fromTripID: values.value(for: "from_trip_id", in: table.indexByHeader),
                toTripID: values.value(for: "to_trip_id", in: table.indexByHeader)
            )
        }
    }

    private func readShapes(
        from feedDirectory: URL,
        including shapeIDs: Set<String>
    ) throws -> [GTFSTimetableShapeEntry] {
        guard let table = try readCSVIfExists(feedDirectory.appendingPathComponent("shapes.txt")) else {
            return []
        }

        var pointsByShapeId: [String: [GTFSTimetableShapePoint]] = [:]
        for line in table.rows {
            let values = CSVRowParser.parse(line)
            guard let id = values.value(for: "shape_id", in: table.indexByHeader), !id.isEmpty,
                  shapeIDs.contains(id),
                  let latitudeText = values.value(for: "shape_pt_lat", in: table.indexByHeader),
                  let longitudeText = values.value(for: "shape_pt_lon", in: table.indexByHeader),
                  let sequenceText = values.value(for: "shape_pt_sequence", in: table.indexByHeader),
                  let latitude = Double(latitudeText),
                  let longitude = Double(longitudeText),
                  let sequence = Int(sequenceText) else {
                continue
            }

            pointsByShapeId[id, default: []].append(
                GTFSTimetableShapePoint(
                    latitude: latitude,
                    longitude: longitude,
                    sequence: sequence,
                    distanceTraveled: Double(
                        values.value(for: "shape_dist_traveled", in: table.indexByHeader) ?? ""
                    )
                )
            )
        }

        return pointsByShapeId.map { shapeId, points in
            GTFSTimetableShapeEntry(id: shapeId, points: points.sorted { $0.sequence < $1.sequence })
        }
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

    private func readCSVIfExists(_ url: URL) throws -> CSVTable? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try readCSV(url)
    }

    private func weekdaySet(from values: [String], in indexByHeader: [String: Int]) -> Set<Int> {
        let headers = [
            "sunday",
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday"
        ]

        return Set(headers.enumerated().compactMap { index, header in
            values.value(for: header, in: indexByHeader) == "1" ? index + 1 : nil
        })
    }

    private func seconds(fromGTFSClock value: String) -> Int? {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private func mode(for routeType: Transit.RouteType) -> String {
        switch routeType {
        case .tram: "tram"
        case .rail: "train"
        case .bus: "bus"
        case .funicular: "funicular"
        default: "unknown"
        }
    }
}

private struct PartialTrip {
    let id: String
    let routeId: String
    let serviceId: String
    let headsign: String?
    let directionId: String?
    let shapeId: String?
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
