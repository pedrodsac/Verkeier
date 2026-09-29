import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Route calculations through the app UI flow", .serialized)
@MainActor
struct RouteCalculationFlowTests {
    @Test("Later pages prioritise departures near their page boundary for realtime")
    func laterPageRealtimeWindow() {
        let boundary = Date(timeIntervalSince1970: 1_800_000_000)
        let later = MobiliteitRouteService.realtimePolicy(
            for: .useCache,
            page: .later(than: boundary, limit: 3)
        )
        let initial = MobiliteitRouteService.realtimePolicy(for: .forceRefresh, page: .initial)

        guard case let .bestEffort(laterConfiguration, laterRefresh) = later,
              case let .bestEffort(initialConfiguration, initialRefresh) = initial else {
            Issue.record("Expected realtime routing for both page types")
            return
        }

        #expect(laterRefresh == .useCache)
        #expect(initialRefresh == .forceRefresh)
        #expect(laterConfiguration.scheduledLookbackSeconds <= 10 * 60)
        #expect(laterConfiguration.minimumForwardHorizonSeconds >= 90 * 60)
        #expect(initialConfiguration.scheduledLookbackSeconds == 20 * 60)
        #expect(initialConfiguration.minimumForwardHorizonSeconds >= 90 * 60)
    }

    @Test("An address remains a coordinate endpoint for nearby-stop routing")
    func addressUsesCoordinateEndpoint() {
        let point = LocationPoint(
            name: "18A Gromscheed, Senningerberg",
            latitude: 49.6541071,
            longitude: 6.2296443
        )

        #expect(MobiliteitRouteService.journeyEndpoint(for: point) == .coordinate(
            Coordinate(latitude: 49.6541071, longitude: 6.2296443),
            label: "18A Gromscheed, Senningerberg"
        ))
    }

    @Test("An explicitly selected transit stop remains exact")
    func selectedStopUsesExactEndpoint() {
        let point = LocationPoint(
            name: "Hamilius",
            latitude: 49.6109868,
            longitude: 6.1257988,
            transitStopID: "hamilius-stop"
        )

        #expect(MobiliteitRouteService.journeyEndpoint(for: point) == .stop(id: "hamilius-stop"))
    }

    @Test("A live-only connection is added and recommended after the timetable result")
    func liveConnectionSupersedesScheduledRecommendation() async {
        let anchor = Date.now
        let origin = LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.12)
        let destination = LocationPoint(name: "Destination", latitude: 49.62, longitude: 6.13)
        let scheduled = testOption(
            id: "scheduled", origin: origin, destination: destination,
            departure: anchor.addingTimeInterval(300),
            arrival: anchor.addingTimeInterval(1_800)
        )
        // The live trip was scheduled too early to catch, but its delay makes
        // it boardable and gets the rider to the destination sooner.
        let delayed = testOption(
            id: "delayed", origin: origin, destination: destination,
            departure: anchor.addingTimeInterval(600),
            arrival: anchor.addingTimeInterval(1_500),
            scheduledDeparture: anchor.addingTimeInterval(-300)
        )
        let viewModel = TransitMapViewModel(now: { anchor })
        viewModel.routeOrigin = RoutePlace(title: "Origin", location: origin, source: .search)
        viewModel.routeDestination = RoutePlace(title: "Destination", location: destination, source: .search)

        await viewModel.calculateRoute(
            using: TwoStageRouteService(scheduled: scheduled, live: delayed), from: nil
        )

        #expect(viewModel.routeOptions.map(\.id).contains(delayed.id))
        #expect(viewModel.selectedRouteOptionID == delayed.id)
        #expect(viewModel.routeErrorMessage == nil)
    }

    private func testOption(
        id: String, origin: LocationPoint, destination: LocationPoint,
        departure: Date, arrival: Date, scheduledDeparture: Date? = nil
    ) -> RouteOption {
        RouteOption(id: id, plan: RoutePlan(
            id: id, origin: origin, destination: destination,
            expectedTravelTime: arrival.timeIntervalSince(departure), distanceMeters: nil,
            legs: [RoutePlan.Leg(
                id: "\(id)-bus", mode: .bus, transportKind: .transit,
                origin: origin, destination: destination,
                departureTime: departure, arrivalTime: arrival,
                scheduledDepartureTime: scheduledDeparture,
                realtimeDepartureTime: scheduledDeparture == nil ? nil : departure,
                realtimeArrivalTime: scheduledDeparture == nil ? nil : arrival,
                liveStatus: scheduledDeparture == nil ? .scheduled : .delayed
            )], dataSource: .local
        ), mapOverlay: nil)
    }

    @Test("The real app flow returns five routes from 18A Gromscheed to Konrad Adenauer")
    func realFeedRouteTapPublishesFiveJourneys() async throws {
        guard let installedFeedDirectory = ProcessInfo.processInfo.environment["ROUTING_TEST_FEED_DIR"] else {
            return
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerkeierRealRouteFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = URL(fileURLWithPath: installedFeedDirectory, isDirectory: true)
        for file in try FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: nil
        ) where file.pathExtension == "sqlite" || file.lastPathComponent == "metadata.json" {
            try FileManager.default.copyItem(
                at: file, to: folder.appendingPathComponent(file.lastPathComponent)
            )
        }
        let gtfsService = MobiliteitGTFSService(directory: folder)
        let status = await gtfsService.feedStatus()
        try #require(status.isReady, "The official GTFS feed could not be installed: \(status.errorMessage ?? status.statusText)")
        let databaseURL = try #require(await gtfsService.routingDatabaseURL())

        let destinationCandidates = await gtfsService.searchStops(query: "Kirchberg, Konrad Adenauer")
        let destinationStop = try #require(destinationCandidates.first { stop in
            stop.fullName.localizedCaseInsensitiveContains("Kirchberg, Konrad Adenauer")
        }, "The real feed did not contain the Kirchberg, Konrad Adenauer stop")

        let feedStore = try GTFSStore(databaseAt: databaseURL)
        let feed = await feedStore.feedInfo()
        let anchor = try #require(routeDate(at: 8, within: feed))
        let routeService = MobiliteitRouteService(gtfsService: gtfsService)
        routeService.prepareForRouting()
        try await routeService.waitUntilPreparedForRouting()
        try await benchmarkBundledGraph(
            folder: folder,
            databaseURL: databaseURL,
            gtfsService: gtfsService,
            destinationStop: destinationStop,
            anchor: anchor
        )

        let defaultsName = "RouteCalculationFlowTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let plannerStore = RoutePlannerStore(defaults: defaults)
        let viewModel = TransitMapViewModel(now: { anchor })

        viewModel.selectRouteOrigin(
            RoutePlace(
                title: "18A Gromscheed",
                subtitle: "Senningerberg",
                location: LocationPoint(
                    name: "18A Gromscheed, Senningerberg",
                    latitude: 49.6541071,
                    longitude: 6.2296443
                ),
                source: .search
            ),
            using: plannerStore
        )
        viewModel.selectRouteDestination(
            RoutePlace(stop: destinationStop, source: .search),
            using: plannerStore
        )
        viewModel.setRoutePlanningTime(.departAt(anchor))

        let routeTask = Task {
            await viewModel.calculateRoute(using: routeService, from: nil)
        }
        await routeTask.value
        try #require(!viewModel.routeOptions.isEmpty)
        #expect(viewModel.routeLoadingPhase == .idle)
        #expect(!viewModel.isCalculatingRoute)
        #expect(viewModel.routeErrorMessage == nil)
        #expect(viewModel.routeOptions.count == 5)
        #expect(viewModel.routeOptions.allSatisfy { $0.plan.dataSource == .local })
        #expect(viewModel.routeOptions.allSatisfy { !$0.transitLegs.isEmpty })
        #expect(viewModel.routeOptions.allSatisfy { option in
            option.mapOverlay?.segments.contains { segment in
                segment.mode != .walking && segment.coordinates.count >= 2
            } == true
        })
        #expect(viewModel.routeOptions.allSatisfy { option in
            !option.routeNames.contains { $0.caseInsensitiveCompare("18A") == .orderedSame }
        })

        let tripSequences = viewModel.routeOptions.map { option in
            option.transitLegs.compactMap(\.tripId)
        }
        #expect(Set(tripSequences).count == 5)

        let ordered = TransitMapViewModel.chronologicallyOrderedOptions(viewModel.routeOptions)
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            let earlierDeparture = try #require(earlier.departureTime)
            let laterDeparture = try #require(later.departureTime)
            #expect(earlierDeparture <= laterDeparture)
        }
        for candidate in ordered {
            let candidateDeparture = try #require(candidate.departureTime)
            let candidateArrival = try #require(candidate.arrivalTime)
            #expect(!ordered.contains { other in
                guard other.id != candidate.id,
                      let otherDeparture = other.departureTime,
                      let otherArrival = other.arrivalTime else {
                    return false
                }
                // Time-only pruning is intentionally superseded: a slightly
                // slower direct or lower-walk journey remains a useful choice.
                return otherDeparture >= candidateDeparture
                    && otherArrival <= candidateArrival
                    && other.transferCount <= candidate.transferCount
                    && other.walkingDistanceMeters <= candidate.walkingDistanceMeters
                    && (otherDeparture > candidateDeparture
                        || otherArrival < candidateArrival
                        || other.transferCount < candidate.transferCount
                        || other.walkingDistanceMeters < candidate.walkingDistanceMeters)
            })
        }

        var calculationCount = 0
        for try await update in routeService.routeCalculationUpdates(
            from: LocationPoint(
                name: "18A Gromscheed, Senningerberg",
                latitude: 49.6541071,
                longitude: 6.2296443
            ),
            to: RoutePlace(stop: destinationStop, source: .search).location,
            time: .departAt(anchor),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh,
            page: .initial
        ) {
            calculationCount += 1
            #expect(!update.options.isEmpty)
        }
        // The downloaded timetable is emitted before the live overlay so a
        // slow connection cannot hold the first result hostage.
        #expect(calculationCount == 2)

        printRouteResults(
            label: "18A Gromscheed → Kirchberg, Konrad Adenauer",
            options: ordered
        )

        // Reproduce the reported Breedewues journey through the app adapter,
        // including its explicit warning for the same-stop tight transfer.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        let breedewuesTime = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 20, minute: 8
        )))
        let exactDestination = try #require(destinationCandidates.first {
            $0.id == "000200417019"
        })
        let breedewues = try await routeService.calculateRoute(
            from: LocationPoint(
                name: "Senningerberg, Breedewues",
                latitude: 49.655126,
                longitude: 6.224556,
                transitStopID: "000200508002"
            ),
            to: RoutePlace(stop: exactDestination, source: .search).location,
            time: .departAt(breedewuesTime),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .scheduleOnly,
            page: .initial
        )
        let selected = try #require(breedewues.selectedOption)
        #expect(selected.routeNames == ["321", "25"])
        #expect(selected.transitLegs.last?.transferWarning?.contains("45 sec") == true)

        let gromscheedStop = try #require(await gtfsService.searchStops(query: "Gromscheed")
            .first { $0.id == "000200508004" })
        let hamiliusStop = try #require(await gtfsService.searchStops(query: "Hamilius")
            .first { $0.id == "000200405020" })
        let gromscheedTime = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 25, hour: 13, minute: 47
        )))
        let gromscheed = try await routeService.calculateRoute(
            from: RoutePlace(stop: gromscheedStop, source: .search).location,
            to: RoutePlace(stop: hamiliusStop, source: .search).location,
            time: .departAt(gromscheedTime),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .scheduleOnly,
            page: .initial
        )
        let walkingOption = try #require(gromscheed.options.first { option in
            option.routeNames.first == "29"
                && option.transitLegs.first?.originStopId == "000200508003"
                && option.transitLegs.count == 2
        })
        #expect(walkingOption.plan.legs.first?.transportKind == .walking)
    }

    private func benchmarkBundledGraph(
        folder: URL,
        databaseURL: URL,
        gtfsService: MobiliteitGTFSService,
        destinationStop: Stop,
        anchor: Date
    ) async throws {
        let datasetManager = RoutingDatasetManager(
            rootURL: folder.appendingPathComponent("walking-graph", isDirectory: true),
            appBuild: 10
        )
        let graphState = await BundledRoutingDatasetInstaller(datasetManager: datasetManager).installIfNeeded()
        guard case .ready = graphState else {
            Issue.record("The bundled walking graph could not be installed for the route benchmark")
            return
        }
        let walkingRouter = LocalFirstWalkingRouter(datasetManager: datasetManager)
        let fixedRealtime = FixedBenchmarkRealtimeProvider()
        let graphRouteService = MobiliteitRouteService(
            databaseURL: databaseURL,
            gtfsService: gtfsService,
            engine: MobiliteitRouteEngine(
                walkingProvider: LocalFirstWalkingRoutingProvider(walkingRouter: walkingRouter),
                realtimeProvider: fixedRealtime
            ),
            walkingRouter: walkingRouter
        )
        let reverseStarted = ContinuousClock.now
        let reverseCalculation = try await graphRouteService.calculateRoute(
            from: RoutePlace(stop: destinationStop, source: .search).location,
            to: LocationPoint(
                name: "18A Gromscheed, Senningerberg",
                latitude: 49.6541071,
                longitude: 6.2296443
            ),
            time: .departAt(anchor),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh,
            page: .initial
        )
        print("Bundled graph cold reverse address route: \(reverseStarted.duration(to: .now)); IDs: \(reverseCalculation.options.map(\.id))")
        #expect(!reverseCalculation.options.isEmpty)
        for run in 1...2 {
            let graphStarted = ContinuousClock.now
            let graphCalculation = try await graphRouteService.calculateRoute(
                from: LocationPoint(
                    name: "18A Gromscheed, Senningerberg",
                    latitude: 49.6541071,
                    longitude: 6.2296443
                ),
                to: RoutePlace(stop: destinationStop, source: .search).location,
                time: .departAt(anchor),
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh,
                page: .initial
            )
            print("Bundled graph route run \(run): \(graphStarted.duration(to: .now)); IDs: \(graphCalculation.options.map(\.id))")
            #expect(!graphCalculation.options.isEmpty)
        }
        #expect(await fixedRealtime.requestCount == 3)
        if ProcessInfo.processInfo.environment["ROUTING_TEST_REAL_LIVE"] == "1",
           let proxyURL = AppConfiguration.current.apiProxyURL {
            let liveService = MobiliteitRouteService(
                databaseURL: databaseURL,
                gtfsService: gtfsService,
                realtimeClient: MobiliteitLiveTransitService(proxyURL: proxyURL).realtimeRoutingClient,
                walkingRouter: walkingRouter
            )
            let liveStarted = ContinuousClock.now
            let liveCalculation = try await liveService.calculateRoute(
                from: RoutePlace(stop: destinationStop, source: .search).location,
                to: LocationPoint(
                    name: "18A Gromscheed, Senningerberg",
                    latitude: 49.6541071,
                    longitude: 6.2296443
                ),
                time: .leaveNow,
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh,
                page: .initial
            )
            print("Live reverse address route: \(liveStarted.duration(to: .now)); IDs: \(liveCalculation.options.map(\.id))")
            print("Live reverse coverage: \(liveCalculation.options.map(\.realtimeCoverage))")
            #expect(!liveCalculation.options.isEmpty)
        }
    }

    @Test("A stalled provider cannot leave the route sheet loading forever")
    func stalledProviderEndsInAnActionableError() async throws {
        let anchor = Date.now
        let viewModel = TransitMapViewModel(
            now: { anchor },
            routeCalculationTimeout: .milliseconds(50)
        )
        viewModel.routeOrigin = RoutePlace(
            title: "18A Gromscheed",
            location: LocationPoint(
                name: "18A Gromscheed, Senningerberg",
                latitude: 49.6541071,
                longitude: 6.2296443
            ),
            source: .search
        )
        viewModel.routeDestination = RoutePlace(
            title: "Kirchberg, Konrad Adenauer",
            location: LocationPoint(
                name: "Kirchberg, Konrad Adenauer",
                latitude: 49.629435,
                longitude: 6.156983,
                transitStopID: "000200417019"
            ),
            stopId: "000200417019",
            source: .selectedStop
        )

        let started = ContinuousClock.now
        await viewModel.calculateRoute(using: NonCooperativeStallingRouteService(), from: nil)
        let elapsed = started.duration(to: .now)

        #expect(elapsed < .seconds(1))
        #expect(viewModel.routeLoadingPhase == .idle)
        #expect(!viewModel.isCalculatingRoute)
        #expect(viewModel.routeOptions.isEmpty)
        #expect(viewModel.routeErrorMessage == "Route calculation is taking too long. Please try again.")

        let origin = try #require(viewModel.routeOrigin?.location)
        let destination = try #require(viewModel.routeDestination?.location)
        let oldRoute = RouteOption(id: "old-route", plan: RoutePlan(
            id: "old-route", origin: origin, destination: destination,
            expectedTravelTime: 600, distanceMeters: nil,
            legs: [RoutePlan.Leg(
                id: "old-bus", mode: .bus, transportKind: .transit,
                origin: origin, destination: destination,
                departureTime: anchor.addingTimeInterval(60),
                arrivalTime: anchor.addingTimeInterval(660)
            )], dataSource: .local
        ), mapOverlay: nil)
        viewModel.unfilteredRouteOptions = [oldRoute]
        viewModel.routeOptions = [oldRoute]
        viewModel.selectedRouteOptionID = oldRoute.id
        await viewModel.calculateRoute(using: ImmediateNoRouteService(), from: nil)
        #expect(viewModel.routeLoadingPhase == .idle)
        #expect(viewModel.routeErrorMessage == "No public transport route was found.")
        #expect(viewModel.routeOptions.isEmpty)
        #expect(viewModel.selectedRouteOptionID == nil)
    }

    private func printRouteResults(label: String, options: [RouteOption]) {
        var lines = ["\n=== \(label) (\(options.count) routes) ==="]
        for (index, option) in options.enumerated() {
            let departure = option.departureTime.map(Self.formatDate) ?? "-"
            let arrival = option.arrivalTime.map(Self.formatDate) ?? "-"
            lines.append("\(index + 1). \(departure)–\(arrival) | source: \(option.plan.dataSource.rawValue)")
            for leg in option.plan.legs {
                let legDeparture = leg.departureTime.map(Self.formatDate) ?? "-"
                let legArrival = leg.arrivalTime.map(Self.formatDate) ?? "-"
                if leg.transportKind == .transit {
                    lines.append(
                        "   transit \(leg.routeName ?? "unknown line") | trip: \(leg.tripId ?? "unknown") | \(legDeparture)–\(legArrival) | \(leg.origin.name ?? "origin") → \(leg.destination.name ?? "destination")"
                    )
                } else {
                    lines.append(
                        "   \(leg.transportKind.rawValue) | \(legDeparture)–\(legArrival) | \(leg.origin.name ?? "origin") → \(leg.destination.name ?? "destination")"
                    )
                }
            }
        }
        print(lines.joined(separator: "\n") + "\n", terminator: "")
    }

    private static func formatDate(_ date: Date) -> String {
        routeTimeFormatter.string(from: date)
    }

    private static let routeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct NonCooperativeStallingRouteService: RouteService {
    func calculateRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) async throws -> RouteCalculation {
        let deadline = Date.now.addingTimeInterval(2)
        while Date.now < deadline {
            _ = 1 + 1
        }
        throw RoutingError.noRouteFound
    }

    @MainActor func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}
}

private struct ImmediateNoRouteService: RouteService {
    func calculateRoute(
        from _: LocationPoint,
        to _: LocationPoint,
        time _: RoutePlanningTime,
        filters _: RoutePlannerFilters,
        realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) async throws -> RouteCalculation {
        throw RoutingError.noPublicTransportRoute
    }

    @MainActor func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}
}

private struct TwoStageRouteService: RouteService {
    let scheduled: RouteOption
    let live: RouteOption

    func calculateRoute(
        from _: LocationPoint, to _: LocationPoint, time _: RoutePlanningTime,
        filters _: RoutePlannerFilters, realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) async throws -> RouteCalculation {
        RouteCalculation(options: [scheduled], selectedOptionID: scheduled.id)
    }

    func routeCalculationUpdates(
        from _: LocationPoint, to _: LocationPoint, time _: RoutePlanningTime,
        filters _: RoutePlannerFilters, realtimeRefreshPolicy _: RouteRealtimeRefreshPolicy,
        page _: RouteSearchPage
    ) -> AsyncThrowingStream<RouteCalculation, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(RouteCalculation(options: [scheduled], selectedOptionID: scheduled.id))
            continuation.yield(RouteCalculation(options: [live], selectedOptionID: live.id))
            continuation.finish()
        }
    }

    @MainActor func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}
}

private actor FixedBenchmarkRealtimeProvider: RealtimeRoutingProvider {
    private(set) var requestCount = 0

    func patches(
        for stopIDs: [String],
        from: Date,
        through: Date,
        refreshPolicy: RealtimeRefreshPolicy
    ) async throws -> RealtimePatchBatch {
        requestCount += 1
        try await Task.sleep(for: .seconds(2))
        let covered = Set(stopIDs)
        return RealtimePatchBatch(
            patches: [],
            requestedStopIDs: covered,
            coveredStopIDs: covered
        )
    }
}

private func routeDate(at hour: Int, within feed: FeedInfo) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
    let dayCount = feed.firstServiceDate.days(until: feed.lastServiceDate)

    // The first feed week can be partial or have sparse service at this stop.
    // Use a representative weekday in the second week when it is available.
    let firstOffset = dayCount >= 14 ? 7 : 0
    for offset in firstOffset...max(firstOffset, dayCount) {
        let serviceDate = feed.firstServiceDate.adding(days: offset)
        guard let candidate = calendar.date(from: DateComponents(
            year: serviceDate.year,
            month: serviceDate.month,
            day: serviceDate.day,
            hour: hour
        )) else {
            continue
        }
        if (2...6).contains(calendar.component(.weekday, from: candidate)) {
            return candidate
        }
    }

    let first = feed.firstServiceDate
    return calendar.date(from: DateComponents(
        year: first.year,
        month: first.month,
        day: first.day,
        hour: hour
    ))
}
