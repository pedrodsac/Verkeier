#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation
import MobiliteitKit
import Observation
import SwiftUI

/// Explicit simulator harness. Uses the production view model, adapter, walking
/// graph and RouteView; recorded ATP transport is the only substituted service.
@Observable @MainActor
final class SimulatorRouteBenchmark {
    static var enabled: Bool { CommandLine.arguments.contains("--routing-benchmark") }
    let viewModel = TransitMapViewModel(routeCalculationTimeout: .seconds(120))
    var status = "Simulator route benchmark — recorded realtime"
    private var service: (any RouteService)?
    var fullMap: Bool { ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_FULL_MAP"] == "1" }

    func run(productionService: any RouteService, walkingRouter: any WalkingRouting, bikes: any BikeShareService) async {
        guard service == nil else { return }
        do {
            let env = ProcessInfo.processInfo.environment
            let scenario = env["ROUTING_BENCHMARK_SCENARIO"] ?? "arrive"
            let gtfs = MobiliteitGTFSService()
            let database: URL
            if let path = env["ROUTING_BENCHMARK_DATABASE"] { database = Self.inputURL(path) }
            else {
                guard let installed = await gtfs.routingDatabaseURL() else { throw RoutingError.timetableUnavailable }
                database = installed
            }
            if env["ROUTING_BENCHMARK_DATABASE"] != nil {
                await (productionService as? MobiliteitRouteService)?.waitForWalkingPreparation()
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [BenchmarkBoardProtocol.self]
            let recordedClient = MobiliteitAPIClient(apiKey: "fixture", baseURL: URL(string: "https://recorded-atp.invalid")!,
                session: URLSession(configuration: config))
            let client: MobiliteitAPIClient
            let liveTransport = scenario.hasPrefix("live-") && env["ROUTING_BENCHMARK_CAPTURE_DIRECTORY"] == nil
            if liveTransport {
                guard let live = MobiliteitLiveTransitService(proxyURL: AppConfiguration.current.apiProxyURL,
                    diagnostics: BenchmarkNetworkRecorder.shared.observer).realtimeRoutingClient
                else { throw RoutingError.noRouteFound }
                client = live
                status = "Simulator route benchmark — live ATP"
            } else { client = recordedClient }
            let production = (env["ROUTING_BENCHMARK_COMPOSITION"] ?? "production") == "production"
            let benchmarkBikes: any BikeShareService
            let bikeInput: String
            if !production { benchmarkBikes = UnavailableBikeShareService(); bikeInput = "unavailable" }
            else if let path = env["ROUTING_BENCHMARK_BIKE_FIXTURE"] {
                benchmarkBikes = BenchmarkBikeShareService(value: try JSONDecoder().decode(BikeShareSnapshot.self,
                    from: Data(contentsOf: Self.inputURL(path))))
                bikeInput = "recorded"
            } else if liveTransport { benchmarkBikes = bikes; bikeInput = "live" }
            else if let snapshot = await bikes.snapshot() {
                benchmarkBikes = BenchmarkBikeShareService(value: snapshot); bikeInput = "cached snapshot"
            } else { benchmarkBikes = UnavailableBikeShareService(); bikeInput = "unavailable" }
            let service: any RouteService
            if production, liveTransport, env["ROUTING_BENCHMARK_BIKE_FIXTURE"] == nil,
               env["ROUTING_BENCHMARK_DATABASE"] == nil,
               env["ROUTING_BENCHMARK_LIVE_CONCURRENCY"] == nil { service = productionService }
            else {
                let walking: any WalkingRouting = production ? walkingRouter : LocalFirstWalkingRouter(datasetManager: RoutingDatasetManager())
                let planner: JourneyPlanner?
                if let value = env["ROUTING_BENCHMARK_LIVE_CONCURRENCY"], let limit = Int(value) {
                    await (productionService as? MobiliteitRouteService)?.waitForWalkingPreparation()
                    planner = JourneyPlanner(walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: walking),
                        realtimeProvider: try HafasRealtimeRoutingProvider(databaseURL: database, client: client,
                            maximumConcurrentBoardRequests: limit, cacheLifetime: 60, requestTimeout: .seconds(4)))
                } else { planner = nil }
                service = MobiliteitRouteService(databaseURL: database, gtfsService: env["ROUTING_BENCHMARK_DATABASE"] == nil ? gtfs : nil,
                    realtimeClient: client, engine: planner, bikeShareService: production ? benchmarkBikes : UnavailableBikeShareService(), walkingRouter: walking,
                    realtimeConcurrency: Int(env["ROUTING_BENCHMARK_LIVE_CONCURRENCY"] ?? "16") ?? 16)
            }
            self.service = service
            let samples = Int(env["ROUTING_BENCHMARK_SAMPLES"] ?? "1") ?? 1
            try configure(scenario)
            let paging = ["paging", "earlier", "arrival-earlier", "arrival-later"].contains(scenario)
            if paging || scenario == "refresh" || scenario == "cached" {
                await viewModel.calculateRoute(using: service, from: nil)
                try await waitForWalkingRefinements()
            }
            var previousRequestID: UUID?
            for sample in 0..<samples {
                if paging {
                    let earlier = scenario == "earlier" || scenario == "arrival-earlier"
                    // A finite timetable can legitimately exhaust a direction.
                    // Re-prime outside the measured operation rather than time
                    // a disabled button which performs no calculation.
                    if earlier ? !viewModel.canLoadEarlierRoutes : !viewModel.canLoadLaterRoutes {
                        await viewModel.calculateRoute(using: service, from: nil)
                        try await waitForWalkingRefinements()
                    }
                    if scenario == "earlier" || scenario == "arrival-earlier" {
                        await viewModel.loadEarlierRoutes(using: service, from: nil)
                    } else {
                        await viewModel.loadLaterRoutes(using: service, from: nil)
                    }
                } else {
                    viewModel.routeOptions = []
                    await viewModel.calculateRoute(using: service, from: nil,
                        realtimeRefreshPolicy: scenario == "cached" ? .useCache : .forceRefresh)
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(120))
                while viewModel.routeDiagnostics?.milliseconds[.firstRender] == nil,
                      viewModel.routeErrorMessage == nil, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard let diagnostics = viewModel.routeDiagnostics,
                      diagnostics.requestID != previousRequestID,
                      diagnostics.milliseconds[.firstRender] != nil,
                      !viewModel.isCalculatingRoute, !viewModel.routeOptions.isEmpty else {
                    throw RoutingError.noRouteFound
                }
                previousRequestID = diagnostics.requestID
                if scenario == "recorded-live", diagnostics.counters[.predictedEvents, default: 0] == 0 {
                    throw RoutingError.noRouteFound
                }
                if scenario == "cached", diagnostics.counters[.networkRequests, default: 0] != 0 {
                    throw RoutingError.noRouteFound
                }
                if fullMap {
                    while viewModel.routeDiagnostics?.milliseconds[.mapRender] == nil, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                }
                // Keep first-render latency, but compare complete walking evidence.
                try await waitForWalkingRefinements()
                if scenario == "urban-bike", !viewModel.supplementalRouteOptions.contains(where: \.isVelohOnly) {
                    throw RoutingError.noRouteFound
                }
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let measured = viewModel.routeDiagnostics ?? diagnostics
                var record: [String: Any] = ["scenario": scenario, "sample": sample,
                    "composition": production ? "production" : "transit", "fullMap": fullMap, "bikeInput": bikeInput,
                    "liveConcurrency": Int(env["ROUTING_BENCHMARK_LIVE_CONCURRENCY"] ?? "16") ?? 16,
                    "spanSemantics": "operation-relative elapsed intervals; http and decode are cumulative concurrent work",
                    "spans": measured.spans.map { ["stage": $0.stage.rawValue, "start_ms": $0.startMilliseconds, "duration_ms": $0.durationMilliseconds] },
                    "passes": diagnostics.searchPasses.map { ["start_ms": $0.startMilliseconds, "duration_ms": $0.durationMilliseconds, "horizon_s": $0.horizonSeconds, "wave": $0.realtimeWave, "rounds": $0.rounds.count, "candidates": $0.candidates] },
                    "supplementalOptions": viewModel.supplementalRouteOptions.map(\.id),
                    "planningTime": viewModel.routePlanningTime.date?.timeIntervalSince1970 ?? 0,
                    "avoidTightTransfers": viewModel.routeFilters.avoidTightTransfers,
                    "includedModes": viewModel.routeFilters.includedModes.map(\.rawValue).sorted(),
                    "recommendedOption": viewModel.selectedRouteOptionID ?? "",
                    "requestID": diagnostics.requestID.uuidString, "total_ms": diagnostics.totalMilliseconds,
                    "stages_ms": Dictionary(uniqueKeysWithValues: measured.milliseconds.map { ($0.key.rawValue, $0.value) }),
                    "transport": try JSONSerialization.jsonObject(with: JSONEncoder().encode(diagnostics.transport)),
                    "canLoadEarlier": viewModel.canLoadEarlierRoutes, "canLoadLater": viewModel.canLoadLaterRoutes,
                    "rounds": diagnostics.rounds.map { ["scan_ms": $0.patternScanMilliseconds, "merge_ms": $0.labelMergeMilliseconds,
                        "prepare_ms": $0.tripPreparationMilliseconds, "alights": $0.alightingChecks, "retained": $0.retainedLabels] },
                    "options": viewModel.routeOptions.map(\.id),
                    "unfilteredJourneys": viewModel.unfilteredRouteOptions.map { option -> [String: Any] in
                        ["id": option.id,
                         "departure": option.departureTime?.timeIntervalSince1970 ?? 0,
                         "arrival": option.arrivalTime?.timeIntervalSince1970 ?? 0,
                         "lines": option.transitLegs.map { $0.routeName ?? "" }]
                    },
                    "journeys": viewModel.routeOptions.map { option -> [String: Any] in
                        ["id": option.id,
                         "departure": option.departureTime?.timeIntervalSince1970 ?? 0,
                         "arrival": option.arrivalTime?.timeIntervalSince1970 ?? 0,
                         "legs": option.plan.legs.map { leg -> [String: Any] in
                             ["line": leg.routeName ?? "walk", "from": leg.origin.name ?? "",
                              "to": leg.destination.name ?? "", "fromStop": leg.originStopId ?? "",
                              "toStop": leg.destinationStopId ?? "",
                              "transferWarning": leg.transferWarning ?? "",
                              "departure": leg.departureTime?.timeIntervalSince1970 ?? 0,
                              "arrival": leg.arrivalTime?.timeIntervalSince1970 ?? 0]
                         }]
                    },
                    "refreshPolicy": scenario == "cached" || paging ? "useCache" : "forceRefresh",
                    "displayedLegs": viewModel.routeOptions.flatMap { option in
                        option.transitLegs.map { leg -> [String: Any] in
                            ["option": option.id, "trip": leg.tripId ?? "", "stop": leg.originStopId ?? "",
                             "line": leg.routeName ?? "", "departureSource": leg.departureTimingSource?.rawValue ?? "scheduled",
                             "arrivalSource": leg.arrivalTimingSource?.rawValue ?? "scheduled", "status": leg.liveStatus.rawValue,
                             "scheduledDeparture": leg.scheduledDepartureTime?.timeIntervalSince1970 ?? 0,
                             "effectiveDeparture": leg.departureTime?.timeIntervalSince1970 ?? 0,
                             "effectiveArrival": leg.arrivalTime?.timeIntervalSince1970 ?? 0]
                        }
                    },
                    "matchingRejections": Dictionary(uniqueKeysWithValues: diagnostics.realtimeMatchingRejections.map { ($0.key.rawValue, $0.value) }),
                    "realtimeCoverage": Dictionary(uniqueKeysWithValues: viewModel.routeOptions.map {
                        ($0.id, $0.realtimeCoverage.rawValue)
                    }),
                    "counters": Dictionary(uniqueKeysWithValues: diagnostics.counters.map { ($0.key.rawValue, $0.value) }), "peak_memory_bytes": usage.ru_maxrss]
                if env["ROUTING_BENCHMARK_FULL_EVIDENCE"] == "1" {
                    record["canonicalPlans"] = try JSONSerialization.jsonObject(with:
                        JSONEncoder().encode(viewModel.unfilteredRouteOptions.map(\.plan)))
                    record["canonicalSupplementalPlans"] = try JSONSerialization.jsonObject(with:
                        JSONEncoder().encode(viewModel.unfilteredSupplementalRouteOptions.map(\.plan)))
                }
                let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("route-benchmark-\(diagnostics.requestID).json")
                try json.write(to: file, options: .atomic)
                // Large accumulated pages can block simctl's console bridge.
                print("ROUTING_BENCHMARK_FILE " + file.path)
                fflush(stdout)
                if liveTransport, env["ROUTING_BENCHMARK_COMPARE_BOARDS"] == "1" {
                    await compareStopBoards(phase: "initial")
                    try await checkBoardCache(using: service)
                    await compareStopBoards(phase: "after-cache")
                }
                status = "\(scenario) sample \(sample + 1)/\(samples): \(Int(diagnostics.totalMilliseconds)) ms"
                await Task.yield()
            }
            if production, let snapshot = await benchmarkBikes.snapshot() {
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("routing-bikes-\(UUID()).json")
                try JSONEncoder().encode(snapshot).write(to: path, options: .atomic)
                print("ROUTING_BIKE_FILE " + path.path)
            }
            print("ROUTING_BENCHMARK_DONE")
            fflush(stdout)
        } catch {
            status = "Benchmark failed"
            if let routing = error as? RoutingError {
                print("ROUTING_BENCHMARK_FAILED \(routing)")
            } else { print("ROUTING_BENCHMARK_FAILED \(String(reflecting: type(of: error)))") }
            fflush(stdout)
        }
    }

    nonisolated static func inputURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return FileManager.default.temporaryDirectory.appendingPathComponent(path)
    }

    private func waitForWalkingRefinements() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while viewModel.hasPendingWalkingRefinements, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard !viewModel.hasPendingWalkingRefinements else { throw RoutingError.noRouteFound }
    }

    private func configure(_ scenario: String) throws {
        let environment = ProcessInfo.processInfo.environment
        var from = LocationPoint(name: "Gromscheed", latitude: 49.6541071, longitude: 6.2296443)
        var to = LocationPoint(name: "Kirchberg Konrad", latitude: 49.6301, longitude: 6.1682, transitStopID: "000200417019")
        let formatter = ISO8601DateFormatter()
        var time: RoutePlanningTime = .departAt(formatter.date(from: "2026-09-30T08:00:00+02:00")!)
        if scenario == "reverse" { swap(&from, &to) }
        if scenario == "arrive" || scenario == "live-arrive" || scenario == "deadline-arrive"
            || scenario == "arrival-earlier" || scenario == "arrival-later" {
            time = .arriveBy(formatter.date(from: "2026-09-30T09:00:00+02:00")!)
        }
        if scenario == "exact" || scenario == "refresh" || scenario == "paging" || scenario == "recorded-live" || scenario == "cached" || scenario == "live-esch" {
            from = .init(name: "Esch", latitude: 49.4959, longitude: 5.9805, transitStopID: "000220402034")
            to = .init(name: "Destination", latitude: 49.611, longitude: 6.13, transitStopID: "000400000095")
            time = .departAt(formatter.date(from: "2026-09-30T18:35:00+02:00")!)
        }
        if scenario == "recorded-live" || scenario == "cached" { time = .departAt(formatter.date(from: "2026-09-30T18:28:00+02:00")!) }
        if scenario == "live-reverse" { swap(&from, &to) }
        if scenario.hasPrefix("live-") {
            time = scenario == "live-arrive" ? .arriveBy(Date.now.addingTimeInterval(3_600)) : .departAt(.now)
        }
        if scenario == "urban-bike" {
            from = .init(name: "Luxembourg Gare", latitude: 49.5991, longitude: 6.1334)
            to = .init(name: "Kirchberg Konrad", latitude: 49.6301, longitude: 6.1682)
        }
        if scenario == "rural" {
            to = .init(name: "Clervaux", latitude: 50.0605, longitude: 6.0316)
        }
        if scenario == "coordinates" {
            to = .init(name: "Kirchberg", latitude: 49.6301, longitude: 6.1682)
        }
        if let value = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_TIME"] {
            guard let anchor = formatter.date(from: value) else { throw CocoaError(.formatting) }
            time = scenario.contains("arrive") ? .arriveBy(anchor) : .departAt(anchor)
        }
        if let value = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_EPOCH"], let seconds = Double(value) {
            let anchor = Date(timeIntervalSince1970: seconds)
            time = scenario.contains("arrive") ? .arriveBy(anchor) : .departAt(anchor)
        }
        if let latitude = environment["ROUTING_BENCHMARK_DESTINATION_LATITUDE"].flatMap(Double.init),
           let longitude = environment["ROUTING_BENCHMARK_DESTINATION_LONGITUDE"].flatMap(Double.init) {
            guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                throw CocoaError(.formatting)
            }
            to = LocationPoint(name: environment["ROUTING_BENCHMARK_DESTINATION_NAME"] ?? "Destination",
                latitude: latitude, longitude: longitude,
                transitStopID: environment["ROUTING_BENCHMARK_DESTINATION_STOP"])
        }
        viewModel.routeFilters = RoutePlannerFilters()
        viewModel.routeFilters.avoidTightTransfers =
            ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_AVOID_TIGHT_TRANSFERS"] == "1"
        viewModel.routeOrigin = .init(title: from.name ?? "Origin", location: from, source: .search)
        viewModel.routeDestination = .init(title: to.name ?? "Destination", location: to, source: .search)
        viewModel.routePlanningTime = time
    }

    /// Opt-in live validation stays outside the displayed-result timing gate.
    /// It goes through the same app service as the departure screen.
    private func compareStopBoards(phase: String) async {
        let live = MobiliteitLiveTransitService(proxyURL: AppConfiguration.current.apiProxyURL,
            diagnostics: BenchmarkNetworkRecorder.shared.observer)
        let legs = viewModel.routeOptions.flatMap(\.transitLegs)
        for stopID in Set(legs.compactMap(\.originStopId)).sorted() {
            guard let leg = legs.first(where: { $0.originStopId == stopID }) else { continue }
            let stop = Stop(id: stopID, name: leg.origin.name ?? stopID, location: leg.origin,
                            dataSource: .gtfs, gtfsStopID: stopID)
            do {
                let board = try await live.departureBoardSnapshot(for: stop, filter: .init())
                let comparisons: [[String: Any]] = legs.filter { $0.originStopId == stopID }.map { leg in
                    let rows = board.departures.filter { departure in
                        departure.lineName == leg.routeName && departure.scheduledDeparture.map { planned in
                            abs(planned.timeIntervalSince(leg.scheduledDepartureTime ?? .distantPast)) <= 90
                        } == true
                    }
                    let row = rows.count == 1 ? rows.first : nil
                    return ["trip": leg.tripId ?? "", "line": leg.routeName ?? "", "matches": rows.count,
                            "routeSource": leg.departureTimingSource?.rawValue ?? "scheduled",
                            "routeDeparture": leg.departureTime?.timeIntervalSince1970 ?? 0,
                            "boardDeparture": row?.realtimeDeparture?.timeIntervalSince1970 ?? 0,
                            "boardCancelled": row?.isCancelled ?? false]
                }
                let result: [String: Any] = ["phase": phase, "stop": stopID, "departures": board.departures.count,
                    "fetchedAt": board.fetchedAt.timeIntervalSince1970, "comparisons": comparisons]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print("ROUTING_BOARD_COMPARISON " + String(decoding: data, as: UTF8.self))
            } catch { print("ROUTING_BOARD_COMPARISON_FAILED \(stopID) \(String(reflecting: type(of: error)))") }
        }
        fflush(stdout)
    }

    private func checkBoardCache(using service: any RouteService) async throws {
        viewModel.routeOptions = []
        await viewModel.calculateRoute(using: service, from: nil, realtimeRefreshPolicy: .useCache)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while viewModel.routeDiagnostics?.milliseconds[.firstRender] == nil,
              viewModel.routeErrorMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let diagnostics = viewModel.routeDiagnostics,
              diagnostics.milliseconds[.firstRender] != nil, !viewModel.routeOptions.isEmpty else {
            throw RoutingError.noRouteFound
        }
        let result: [String: Any] = ["total_ms": diagnostics.totalMilliseconds,
            "counters": Dictionary(uniqueKeysWithValues: diagnostics.counters.map { ($0.key.rawValue, $0.value) }),
            "matchingRejections": Dictionary(uniqueKeysWithValues: diagnostics.realtimeMatchingRejections.map { ($0.key.rawValue, $0.value) }),
            "legs": viewModel.routeOptions.flatMap { option in option.transitLegs.map { leg -> [String: Any] in
                ["option": option.id, "trip": leg.tripId ?? "", "stop": leg.originStopId ?? "", "line": leg.routeName ?? "",
                 "source": leg.departureTimingSource?.rawValue ?? "scheduled",
                 "departure": leg.departureTime?.timeIntervalSince1970 ?? 0]
            } }]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("route-cache-comparison-\(diagnostics.requestID).json")
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: file, options: .atomic)
        print("ROUTING_CACHED_COMPARISON_FILE " + file.path)
        fflush(stdout)
    }

    func recordMapRendered(_ id: UUID) {
        guard viewModel.routeDiagnostics?.requestID == id,
              viewModel.routeDiagnostics?.milliseconds[.mapRender] == nil,
              let published = viewModel.routePublishedAt else { return }
        viewModel.routeDiagnostics?.record(.mapRender, since: published)
    }

    var presentation: RoutePresentationModel {
        .init(selectedStop: nil, origin: viewModel.routeOrigin, destination: viewModel.routeDestination,
            currentLocation: nil, favouritePlaces: [], nearbyPlaces: [], recentPlaces: [], commutePresets: [],
            filters: viewModel.routeFilters, planningTime: viewModel.routePlanningTime,
            routeOptions: viewModel.routeOptions, browsingWindow: viewModel.routeBrowsingWindow,
            supplementalRouteOptions: viewModel.supplementalRouteOptions,
            isLoadingEarlierRoutes: viewModel.isLoadingEarlierRoutes, isLoadingLaterRoutes: viewModel.isLoadingLaterRoutes,
            canLoadEarlierRoutes: viewModel.canLoadEarlierRoutes, canLoadLaterRoutes: viewModel.canLoadLaterRoutes,
            alerts: [], selectedRouteOptionID: viewModel.selectedRouteOptionID,
            loadingPhase: viewModel.routeLoadingPhase, errorMessage: viewModel.routeErrorMessage,
            statusMessage: viewModel.routeStatusMessage, lastCalculatedAt: viewModel.routeLastCalculatedAt,
            diagnosticRequestID: viewModel.routeDiagnostics?.requestID, resultsRendered: viewModel.recordRouteResultsRendered)
    }
}

#endif
