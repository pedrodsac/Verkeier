import Foundation
import MobiliteitKit
import Testing
@testable import Verkeier

@Suite("Route calculations through the app UI flow", .serialized)
@MainActor
struct RouteCalculationFlowTests {
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

    @Test("The real app flow returns five routes from 18A Gromscheed to Konrad Adenauer")
    func realFeedRouteTapPublishesFiveJourneys() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerkeierRealRouteFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let gtfsService = MobiliteitGTFSService(directory: folder)
        let status = await gtfsService.refreshIfNeeded(force: true)
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

        let started = ContinuousClock.now
        let routeTask = Task {
            await viewModel.calculateRoute(using: routeService, from: nil)
        }
        while viewModel.routeOptions.isEmpty,
              started.duration(to: .now) < .seconds(15) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let firstResultElapsed = started.duration(to: .now)
        #expect(!viewModel.routeOptions.isEmpty)
        #expect(firstResultElapsed < .seconds(5))

        await routeTask.value
        let elapsed = started.duration(to: .now)

        #expect(elapsed < .seconds(15))
        #expect(viewModel.routeLoadingPhase == .idle)
        #expect(!viewModel.isCalculatingRoute)
        #expect(viewModel.routeErrorMessage == nil)
        #expect(viewModel.routeOptions.count == 5)
        #expect(viewModel.routeOptions.allSatisfy { $0.plan.dataSource == .local })
        #expect(viewModel.routeOptions.allSatisfy { !$0.transitLegs.isEmpty })
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
                return otherDeparture > candidateDeparture && otherArrival < candidateArrival
            })
        }

        printRouteResults(
            label: "18A Gromscheed → Kirchberg, Konrad Adenauer",
            options: ordered
        )
    }

    @Test("A stalled provider cannot leave the route sheet loading forever")
    func stalledProviderEndsInAnActionableError() async {
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

private func routeDate(at hour: Int, within feed: FeedInfo) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
    let dayCount = feed.firstServiceDate.days(until: feed.lastServiceDate)

    for offset in 0...max(0, dayCount) {
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
