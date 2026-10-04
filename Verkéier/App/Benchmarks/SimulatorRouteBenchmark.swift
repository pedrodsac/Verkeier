#if targetEnvironment(simulator)
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
    private var service: MobiliteitRouteService?

    func run() async {
        guard service == nil else { return }
        do {
            let env = ProcessInfo.processInfo.environment
            let scenario = env["ROUTING_BENCHMARK_SCENARIO"] ?? "arrive"
            let gtfs = MobiliteitGTFSService()
            guard let database = await gtfs.routingDatabaseURL() else { throw RoutingError.timetableUnavailable }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [BenchmarkBoardProtocol.self]
            let recordedClient = MobiliteitAPIClient(apiKey: "fixture", baseURL: URL(string: "https://recorded-atp.invalid")!,
                session: URLSession(configuration: config))
            let client: MobiliteitAPIClient
            if scenario.hasPrefix("live-") {
                guard let live = MobiliteitLiveTransitService(proxyURL: AppConfiguration.current.apiProxyURL).realtimeRoutingClient
                else { throw RoutingError.noRouteFound }
                client = live
                status = "Simulator route benchmark — live ATP"
            } else { client = recordedClient }
            let walking = LocalFirstWalkingRouter(datasetManager: RoutingDatasetManager())
            let service = MobiliteitRouteService(databaseURL: database, gtfsService: gtfs,
                realtimeClient: client, walkingRouter: walking)
            self.service = service
            let samples = Int(env["ROUTING_BENCHMARK_SAMPLES"] ?? "1") ?? 1
            configure(scenario)
            let paging = ["paging", "earlier", "arrival-earlier", "arrival-later"].contains(scenario)
            if paging || scenario == "refresh" || scenario == "cached" {
                await viewModel.calculateRoute(using: service, from: nil)
                try await Task.sleep(for: .seconds(1))
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
                        try await Task.sleep(for: .milliseconds(500))
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
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let record: [String: Any] = ["scenario": scenario, "sample": sample,
                    "requestID": diagnostics.requestID.uuidString, "total_ms": diagnostics.totalMilliseconds,
                    "stages_ms": Dictionary(uniqueKeysWithValues: diagnostics.milliseconds.map { ($0.key.rawValue, $0.value) }),
                    "rounds": diagnostics.rounds.map { ["scan_ms": $0.patternScanMilliseconds, "merge_ms": $0.labelMergeMilliseconds,
                        "prepare_ms": $0.tripPreparationMilliseconds, "alights": $0.alightingChecks, "retained": $0.retainedLabels] },
                    "options": viewModel.routeOptions.map(\.id),
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
                let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("route-benchmark-\(diagnostics.requestID).json")
                try json.write(to: file, options: .atomic)
                // Large accumulated pages can block simctl's console bridge.
                print("ROUTING_BENCHMARK_FILE " + file.path)
                fflush(stdout)
                if scenario.hasPrefix("live-") {
                    await compareStopBoards(phase: "initial")
                    try await checkBoardCache(using: service)
                    await compareStopBoards(phase: "after-cache")
                }
                status = "\(scenario) sample \(sample + 1)/\(samples): \(Int(diagnostics.totalMilliseconds)) ms"
                // Geometry refinement is outside the gate. Let it finish before
                // another sample, to avoid measuring concurrent search work.
                try await Task.sleep(for: .milliseconds(500))
            }
            print("ROUTING_BENCHMARK_DONE")
            fflush(stdout)
        } catch {
            status = "Benchmark failed: \(error)"
            print("ROUTING_BENCHMARK_FAILED \(error)")
            fflush(stdout)
        }
    }

    private func configure(_ scenario: String) {
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
        if scenario == "rural" {
            to = .init(name: "Clervaux", latitude: 50.0605, longitude: 6.0316)
        }
        if scenario == "coordinates" {
            to = .init(name: "Kirchberg", latitude: 49.6301, longitude: 6.1682)
        }
        viewModel.routeOrigin = .init(title: from.name ?? "Origin", location: from, source: .search)
        viewModel.routeDestination = .init(title: to.name ?? "Destination", location: to, source: .search)
        viewModel.routePlanningTime = time
    }

    /// Opt-in live validation stays outside the displayed-result timing gate.
    /// It goes through the same app service as the departure screen.
    private func compareStopBoards(phase: String) async {
        let live = MobiliteitLiveTransitService(proxyURL: AppConfiguration.current.apiProxyURL)
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
            } catch { print("ROUTING_BOARD_COMPARISON_FAILED \(stopID) \(error)") }
        }
        fflush(stdout)
    }

    private func checkBoardCache(using service: MobiliteitRouteService) async throws {
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

    var presentation: RoutePresentationModel {
        .init(selectedStop: nil, origin: viewModel.routeOrigin, destination: viewModel.routeDestination,
            currentLocation: nil, favouritePlaces: [], nearbyPlaces: [], recentPlaces: [], commutePresets: [],
            filters: viewModel.routeFilters, planningTime: viewModel.routePlanningTime,
            routeOptions: viewModel.routeOptions, browsingWindow: viewModel.routeBrowsingWindow,
            isLoadingEarlierRoutes: viewModel.isLoadingEarlierRoutes, isLoadingLaterRoutes: viewModel.isLoadingLaterRoutes,
            canLoadEarlierRoutes: viewModel.canLoadEarlierRoutes, canLoadLaterRoutes: viewModel.canLoadLaterRoutes,
            alerts: [], selectedRouteOptionID: viewModel.selectedRouteOptionID,
            loadingPhase: viewModel.routeLoadingPhase, errorMessage: viewModel.routeErrorMessage,
            statusMessage: viewModel.routeStatusMessage, lastCalculatedAt: viewModel.routeLastCalculatedAt,
            diagnosticRequestID: viewModel.routeDiagnostics?.requestID, resultsRendered: viewModel.recordRouteResultsRendered)
    }
}

struct SimulatorRouteBenchmarkView: View {
    @State private var benchmark = SimulatorRouteBenchmark()
    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            ScrollView {
                Text(benchmark.status).font(.caption).padding()
                RouteView(viewModel: benchmark.presentation, actions: RouteActions()).padding()
            }.presentationDetents([.large]).interactiveDismissDisabled()
        }.task { await benchmark.run() }
    }
}

private nonisolated final class BenchmarkBoardProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "recorded-atp.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // A silent fixture exercises the entire acquisition budget; URLSession
        // cancellation at the deadline calls stopLoading and ends the request.
        if ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_SCENARIO"] == "deadline-arrive" { return }
        do {
            let stop = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "id" }?.value
            let body: Data
            if stop == "000220402034", let path = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_FIXTURE"] {
                body = try Data(contentsOf: URL(fileURLWithPath: path))
            } else { body = Data("{\"Departure\":[]}".utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
