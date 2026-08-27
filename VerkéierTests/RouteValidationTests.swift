import Foundation
import Testing
@testable import Verkeier

/// Console-only validation of the public-transport routing engine against the real
/// Luxembourg GTFS feed, for benchmarking versus mobiliteit.lu. Runs on the
/// "My Mac (Designed for iPhone)" target — no simulator required.
///
/// Self-contained: downloads the GTFS feed, unzips it, and builds the timetable
/// index entirely inside the app-sandbox temp dir (the only writable location on
/// the macOS "Designed for iPhone" host), then prints the planned route.
///
/// Gated by env so it never runs (or hits the network) in the normal suite:
///   LUXTRANSIT_VALIDATE=1   — required to run
///   LUXTRANSIT_GTFS_URL     — optional GTFS .zip URL (defaults to the latest known feed)
///   LUXTRANSIT_DEPART       — optional "yyyy-MM-dd HH:mm" Europe/Luxembourg depart time
struct RouteValidationTests {
    private static let defaultFeedURL =
        "https://download.data.public.lu/resources/horaires-et-arrets-des-transport-publics-gtfs/20260625-054655/gtfs-20260624-20260823.zip"

    @Test func senningerbergCharlysStatiounToHamilius() async throws {
        guard ProcessInfo.processInfo.environment["LUXTRANSIT_VALIDATE"] == "1" else {
            print("[route-validation] LUXTRANSIT_VALIDATE != 1 — skipping.")
            return
        }

        let payload = try await loadTimetable()
        print("[route-validation] timetable: \(payload.stops.count) stops, "
            + "\(payload.routes.count) routes, \(payload.trips.count) trips")

        let depart = departTime()
        let origin = LocationPoint(
            id: "000200508003",
            name: "Senningerberg, Charlys Statioun",
            latitude: 49.649996,
            longitude: 6.226089
        )
        let destination = LocationPoint(
            id: "000200405020",
            name: "Hamilius",
            latitude: 49.611504,
            longitude: 6.125976
        )

        let service = PublicTransportRouteService(
            gtfsService: PayloadGTFSService(payload: payload),
            atpClient: EmptyATPClient(),
            roadRouteProvider: NoRoadRouteProvider(),
            now: { depart }
        )

        let calculation = try await service.calculateRoute(
            from: origin,
            to: destination,
            time: .departAt(depart),
            filters: RoutePlannerFilters()
        )

        printRoute(calculation, depart: depart)
        #expect(!calculation.options.isEmpty)
    }

    @Test func senningerbergGromscheedToMerschArriveBy() async throws {
        guard ProcessInfo.processInfo.environment["LUXTRANSIT_VALIDATE"] == "1" else {
            print("[route-validation] LUXTRANSIT_VALIDATE != 1 — skipping.")
            return
        }

        let payload = try await loadTimetable()
        let originStop = try #require(payload.stops.first {
            $0.name.normalizedForSearch == "senningerberg, gromscheed".normalizedForSearch
        })
        let destinationStop = try #require(payload.stops.first {
            $0.name.normalizedForSearch == "mersch, gare".normalizedForSearch
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        let deadline = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 23,
            hour: 18,
            minute: 50
        )))
        let origin = LocationPoint(
            id: originStop.id,
            name: originStop.name,
            latitude: originStop.latitude,
            longitude: originStop.longitude
        )
        let destination = LocationPoint(
            id: destinationStop.id,
            name: destinationStop.name,
            latitude: destinationStop.latitude,
            longitude: destinationStop.longitude
        )
        let service = PublicTransportRouteService(
            gtfsService: PayloadGTFSService(payload: payload),
            atpClient: EmptyATPClient(),
            roadRouteProvider: NoRoadRouteProvider(),
            now: { deadline }
        )

        var calculation: RouteCalculation?
        var timings: [Double] = []
        for _ in 0 ..< 10 {
            let started = DispatchTime.now().uptimeNanoseconds
            calculation = try await service.calculateRoute(
                from: origin,
                to: destination,
                time: .arriveBy(deadline),
                filters: RoutePlannerFilters()
            )
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            timings.append(Double(elapsed) / 1_000_000)
        }

        let result = try #require(calculation)
        let medianMilliseconds = timings.sorted()[timings.count / 2]
        print("[route-validation] arrive-by 10-run median: \(Int(medianMilliseconds)) ms")
        printRoute(result, depart: deadline)

        let selected = try #require(result.options.first)
        let selectedDeparture = try #require(selected.departureTime)
        let selectedArrival = try #require(selected.arrivalTime)
        #expect(selectedArrival <= deadline)
        #expect(result.options.filter { ($0.arrivalTime ?? .distantFuture) <= deadline }.allSatisfy {
            ($0.departureTime ?? .distantPast) <= selectedDeparture
        })
        #expect(zip(selected.plan.legs, selected.plan.legs.dropFirst()).allSatisfy { pair in
            (pair.0.transportKind == .walking && pair.1.transportKind == .walking) == false
        })
        let dommeldangeWalks = selected.plan.legs.filter { leg in
            guard leg.transportKind == .walking else { return false }
            return leg.origin.name?.localizedCaseInsensitiveContains("Dommeldange") == true
                || leg.destination.name?.localizedCaseInsensitiveContains("Dommeldange") == true
        }
        let summary = ([
            "10-run median: \(Int(medianMilliseconds)) ms",
            "Selected: \(selectedDeparture) -> \(selectedArrival)",
            "Dommeldange walks: \(dommeldangeWalks.count)"
        ] + selected.plan.legs.map { leg in
            "\(leg.transportKind.rawValue): \(leg.origin.name ?? leg.origin.id) -> "
                + "\(leg.destination.name ?? leg.destination.id) "
                + "[\(leg.departureTime?.description ?? "-") -> \(leg.arrivalTime?.description ?? "-")]"
        }).joined(separator: "\n")
        Attachment.record(summary, named: "Senningerberg-Mersch-arrive-by.txt")
        #expect(dommeldangeWalks.count == 1)
    }

    @Test func scheduledProfileSearchP95StaysUnderFiveHundredMilliseconds() async throws {
        guard ProcessInfo.processInfo.environment["LUXTRANSIT_VALIDATE"] == "1" else {
            print("[route-validation] LUXTRANSIT_VALIDATE != 1 — skipping.")
            return
        }

        let payload = try await loadTimetable()
        func stop(id: String? = nil, name: String? = nil) throws -> LocationPoint {
            let entry = try #require(payload.stops.first { candidate in
                if let id { return candidate.id == id }
                return candidate.name.normalizedForSearch == name?.normalizedForSearch
            })
            return LocationPoint(
                id: entry.id,
                name: entry.name,
                latitude: entry.latitude,
                longitude: entry.longitude
            )
        }
        func date(hour: Int, minute: Int) throws -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
            return try #require(calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 21,
                hour: hour,
                minute: minute
            )))
        }

        let charlys = try stop(id: "000200508003")
        let gromscheed = try stop(name: "Senningerberg, Gromscheed")
        let hamilius = try stop(id: "000200405020")
        let mersch = try stop(name: "Mersch, Gare")
        let queries: [(String, LocationPoint, LocationPoint, Date)] = [
            ("urban", charlys, hamilius, try date(hour: 8, minute: 0)),
            ("regional", gromscheed, mersch, try date(hour: 8, minute: 0)),
            ("transfer", charlys, mersch, try date(hour: 17, minute: 0)),
            ("late-night", gromscheed, hamilius, try date(hour: 22, minute: 0))
        ]
        let service = PublicTransportRouteService(
            gtfsService: PayloadGTFSService(payload: payload),
            atpClient: EmptyATPClient(),
            roadRouteProvider: NoRoadRouteProvider(),
            now: { queries[0].3 }
        )

        var timings: [Double] = []
        for (label, origin, destination, departure) in queries {
            _ = try await service.calculateRoute(
                from: origin,
                to: destination,
                time: .departAt(departure),
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .useCache
            )
            for _ in 0 ..< 5 {
                let started = DispatchTime.now().uptimeNanoseconds
                let result = try await service.calculateRoute(
                    from: origin,
                    to: destination,
                    time: .departAt(departure),
                    filters: RoutePlannerFilters(),
                    realtimeRefreshPolicy: .useCache
                )
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                timings.append(elapsed)
                let departures = result.options.compactMap(\.departureTime)
                #expect((1 ... 5).contains(result.options.count))
                #expect(zip(departures, departures.dropFirst()).allSatisfy { $0.0 < $0.1 })
                print("[route-validation] \(label): \(Int(elapsed)) ms")
            }
        }

        let ordered = timings.sorted()
        let percentileIndex = min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1)
        let p95 = ordered[percentileIndex]
        print("[route-validation] scheduled profile p95: \(Int(p95)) ms")
        #expect(p95 <= 500)
    }

    // MARK: - Index loading (download → unzip → build, all in sandbox temp)

    private func loadTimetable() async throws -> GTFSTimetableIndexPayload {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(
            "luxtransit-validation",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let cacheURL = work.appendingPathComponent("timetable-index.json")

        if let data = try? Data(contentsOf: cacheURL),
           let payload = try? JSONDecoder.gtfsLocal.decode(GTFSTimetableIndexPayload.self, from: data) {
            print("[route-validation] loaded cached index \(cacheURL.path)")
            return payload
        }

        let feedString = ProcessInfo.processInfo.environment["LUXTRANSIT_GTFS_URL"] ?? Self.defaultFeedURL
        let feedURL = try #require(URL(string: feedString))
        let zipURL = work.appendingPathComponent("gtfs.zip")
        if !FileManager.default.fileExists(atPath: zipURL.path) {
            print("[route-validation] downloading \(feedString) …")
            try await GTFSDownloadService().download(from: feedURL, to: zipURL)
        }

        let extracted = work.appendingPathComponent("feed", isDirectory: true)
        try? FileManager.default.removeItem(at: extracted)
        try GTFSArchiveService().unzip(zipURL, to: extracted)
        let feedDir = try GTFSValidator().validatedFeedDirectory(in: extracted)
        // Shapes are only used for map overlays; dropping them keeps the index small
        // and the JSON decode fast for this text-only validation.
        try? FileManager.default.removeItem(at: feedDir.appendingPathComponent("shapes.txt"))

        print("[route-validation] building index from \(feedDir.path) …")
        try GTFSIndexBuilder().buildTimetableIndex(from: feedDir, to: cacheURL)
        let data = try Data(contentsOf: cacheURL)
        return try JSONDecoder.gtfsLocal.decode(GTFSTimetableIndexPayload.self, from: data)
    }

    private func departTime() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        if let override = ProcessInfo.processInfo.environment["LUXTRANSIT_DEPART"] {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = formatter.date(from: override) { return date }
        }
        // Default: Monday 2026-06-29 08:00, within the feed's service window.
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 29, hour: 8, minute: 0
        ))!
    }

    // MARK: - Output

    private func printRoute(_ calculation: RouteCalculation, depart: Date) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "EEE HH:mm"

        func clock(_ date: Date?) -> String {
            date.map { formatter.string(from: $0) } ?? "--:--"
        }

        print("\n========== APP ROUTE: Senningerberg, Charlys Statioun → Hamilius ==========")
        print("Depart query: \(clock(depart))   Options: \(calculation.options.count)\n")

        for (index, option) in calculation.options.prefix(5).enumerated() {
            let legs = option.plan.legs
            let start = legs.compactMap(\.departureTime).first
            let end = legs.compactMap(\.arrivalTime).last
            let minutes = option.plan.expectedTravelTime.map { Int($0 / 60) } ?? 0
            print("--- Option \(index + 1): \(clock(start)) → \(clock(end))  "
                + "(\(minutes) min, \(option.transferCount) transfer\(option.transferCount == 1 ? "" : "s")) ---")
            for leg in legs {
                let line = leg.transportKind == .transit
                    ? "  🚍 \(leg.routeName ?? leg.routeId ?? "?")  \(clock(leg.departureTime)) \(stopName(leg.originStopId, leg.origin)) "
                    + "→ \(clock(leg.arrivalTime)) \(stopName(leg.destinationStopId, leg.destination))"
                    + "  (trip \(leg.tripId ?? "?"))"
                    + (leg.headsign.map { "  [→ \($0)]" } ?? "")
                    : "  🚶 walk \(Int(leg.distanceMeters ?? 0)) m  \(clock(leg.departureTime)) → \(clock(leg.arrivalTime))"
                print(line)
            }
            print("")
        }
        print("===========================================================================\n")
    }

    private func stopName(_ id: String?, _ point: LocationPoint) -> String {
        point.name ?? id ?? "?"
    }
}

// MARK: - Offline test doubles

/// GTFSService backed by a fixed timetable payload. Only the methods the routing
/// engine touches are meaningful; the rest return empties.
private struct PayloadGTFSService: GTFSService {
    let payload: GTFSTimetableIndexPayload

    nonisolated func searchStops(query _: String) async -> [Stop] {
        []
    }

    nonisolated func stopsForMap(
        center _: LocationPoint, latitudeDelta _: Double, longitudeDelta _: Double, limit _: Int
    ) async -> [Stop] {
        []
    }

    nonisolated func allStops() async -> [Stop] {
        []
    }

    nonisolated func routesForStop(id _: String) async -> [TransitRoute] {
        []
    }

    nonisolated func stop(id: String) async -> Stop? {
        payload.stops.first { $0.id == id }.map {
            Stop(id: $0.id, name: $0.name, location: $0.location, modes: [], dataSource: .gtfs)
        }
    }

    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload? {
        payload
    }
}

/// Skips MapKit road routing — irrelevant to schedule/structure validation and would
/// require a network round-trip per leg.
private struct NoRoadRouteProvider: RoadRouteProviding {
    nonisolated func roadRouteCoordinates(
        from _: LocationPoint, to _: LocationPoint, transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        nil
    }
}
