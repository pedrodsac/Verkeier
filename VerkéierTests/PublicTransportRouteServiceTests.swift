import Foundation
import Testing
@testable import Verkeier

struct PublicTransportRouteServiceTests {
    /// Fast, deterministic route-engine probe for the Mobiliteit.lu comparison
    /// scenario. Run without launching the app with:
    ///
    ///     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:VerkéierTests/PublicTransportRouteServiceTests/senningerbergGromscheedToHamiliusReturnsMobiliteitStyleAlternatives
    @Test func senningerbergGromscheedToHamiliusReturnsMobiliteitStyleAlternatives() async throws {
        let now = luxembourgDate(hour: 21, minute: 30)
        let origin = LocationPoint(
            id: "senningerberg-gromscheed",
            name: "Senningerberg, Gromscheed",
            latitude: 49.65,
            longitude: 6.22
        )
        let destination = LocationPoint(
            id: "hamilius-bus",
            name: "Hamilius",
            latitude: 49.61,
            longitude: 6.13
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeMobiliteitStyleTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: origin,
            to: destination,
            time: .departAt(now),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache
        )
        let departures = calculation.options.compactMap(\.departureTime)

        #expect((1 ... 5).contains(calculation.options.count))
        #expect(zip(departures, departures.dropFirst()).allSatisfy { $0.0 < $0.1 })
        #expect(calculation.options.allSatisfy { !$0.transitLegs.isEmpty })
    }

    @Test func departureProfileReturnsFiveConditionalFastestJourneys() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let specifications: [(String, Int, Int)] = [
            ("R-slow", 5, 40),
            ("R-first", 10, 25),
            ("R-dominated", 15, 35),
            ("R-second", 20, 30),
            ("R-third", 30, 38),
            ("R-fourth", 40, 45),
            ("R-fifth", 50, 55)
        ]
        let timetable = makeTimetable(
            routes: specifications.map { makeRoute(id: $0.0, shortName: $0.0) },
            trips: specifications.enumerated().map { index, specification in
                timedTrip(id: "T-\(index)", routeId: specification.0, stops: [
                    ("S1", t(8, specification.1), t(8, specification.1)),
                    ("S2", t(8, specification.2), t(8, specification.2))
                ])
            }
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .departAt(now)
        )

        #expect(calculation.options.count == 5)
        #expect(calculation.options.compactMap { $0.transitLegs.first?.routeId } == [
            "R-first", "R-second", "R-third", "R-fourth", "R-fifth"
        ])
        let departures = calculation.options.compactMap(\.departureTime)
        #expect(zip(departures, departures.dropFirst()).allSatisfy { $0.0 < $0.1 })
    }

    @Test func laterPageReturnsThreeDeparturesStrictlyAfterBoundary() async throws {
        let boundary = luxembourgDate(hour: 8, minute: 40)
        let departureMinutes = [30, 40, 50, 60, 70, 80]
        let timetable = makeTimetable(
            routes: [makeRoute(id: "R-page", shortName: "P")],
            trips: departureMinutes.map { minute in
                makeTrip(id: "T-\(minute)", routeId: "R-page", departure: t(8, minute))
            }
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { boundary },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(boundary),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache,
            page: .later(than: boundary, limit: 3)
        )

        #expect(calculation.options.count == 3)
        #expect(calculation.options.allSatisfy { ($0.departureTime ?? .distantPast) > boundary })
        #expect(calculation.options.contains { ($0.arrivalTime ?? .distantPast) > boundary })
    }

    @Test func earlierPageReturnsLatestThreeDeparturesStrictlyBeforeBoundary() async throws {
        let boundary = luxembourgDate(hour: 8, minute: 40)
        let departureMinutes = [0, 10, 20, 30, 40]
        let timetable = makeTimetable(
            routes: [makeRoute(id: "R-page", shortName: "P")],
            trips: departureMinutes.map { minute in
                makeTrip(id: "T-\(minute)", routeId: "R-page", departure: t(8, minute))
            }
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { boundary },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache,
            page: .earlier(than: boundary, limit: 3)
        )

        #expect(calculation.options.count == 3)
        #expect(calculation.options.allSatisfy { ($0.departureTime ?? .distantFuture) < boundary })
        #expect(calculation.options.compactMap(\.departureTime) == [
            luxembourgDate(hour: 8, minute: 30),
            luxembourgDate(hour: 8, minute: 20),
            luxembourgDate(hour: 8, minute: 10)
        ])
    }

    @Test func laterPageFindsGTFSDepartureAfterMidnight() async throws {
        let boundary = luxembourgDate(hour: 23, minute: 55)
        let timetable = makeTimetable(
            routes: [makeRoute(id: "R-night-page", shortName: "N")],
            trips: [makeTrip(id: "T-night-page", routeId: "R-night-page", departure: t(24, 10))]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { boundary },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .departAt(boundary),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache,
            page: .later(than: boundary, limit: 3)
        )

        let departure = try #require(calculation.options.first?.departureTime)
        #expect(departure == luxembourgDate(hour: 24, minute: 10))
    }

    @Test func pagesAcrossMidnightUsingAdjacentCalendarServices() async throws {
        let services = [GTFSTimetableServiceEntry(
            id: "WEEK",
            weekdays: [],
            startDate: nil,
            endDate: nil,
            addedDates: ["20260614", "20260615"],
            removedDates: []
        )]
        let origin = LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let laterBoundary = luxembourgDate(hour: 23, minute: 55)
        let laterService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable(
                routes: [makeRoute(id: "R-next", shortName: "N")],
                trips: [makeTrip(id: "T-next", routeId: "R-next", departure: t(0, 10))],
                services: services
            )),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { laterBoundary },
            concurrency: .serial
        )
        let later = try await laterService.calculateRoute(
            from: origin,
            to: destination,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache,
            page: .later(than: laterBoundary, limit: 3)
        )
        #expect(later.options.first?.departureTime == luxembourgDate(hour: 24, minute: 10))

        let earlierBoundary = luxembourgDate(hour: 24, minute: 5)
        let earlierService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable(
                routes: [makeRoute(id: "R-prev", shortName: "P")],
                trips: [makeTrip(id: "T-prev", routeId: "R-prev", departure: t(23, 50))],
                services: services
            )),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { earlierBoundary },
            concurrency: .serial
        )
        let earlier = try await earlierService.calculateRoute(
            from: origin,
            to: destination,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .useCache,
            page: .earlier(than: earlierBoundary, limit: 3)
        )
        #expect(earlier.options.first?.departureTime == luxembourgDate(hour: 23, minute: 50))
    }

    @Test func liveRefreshKeepsRoutesWithoutCompleteRealtimeCoverage() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let departureMinutes = [10, 20, 30, 40, 50]
        let timetable = makeTimetable(
            routes: departureMinutes.map { makeRoute(id: "R-\($0)", shortName: "\($0)") },
            trips: departureMinutes.map { minute in
                timedTrip(id: "T-\(minute)", routeId: "R-\(minute)", stops: [
                    ("S1", t(8, minute), t(8, minute)),
                    ("S2", t(8, minute + 10), t(8, minute + 10))
                ])
            }
        )
        let liveDeparture = Departure(
            id: "live-10",
            stopId: "S1",
            routeId: "R-10",
            lineName: "10",
            destination: "Central",
            scheduledDeparture: luxembourgDate(hour: 8, minute: 10),
            realtimeDeparture: luxembourgDate(hour: 8, minute: 11),
            delayMinutes: 1,
            dataSource: .atpOpenAPI
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(departuresByStopId: ["S1": [liveDeparture]]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .departAt(now),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        #expect(calculation.options.count == 5)
        #expect(calculation.options.contains { $0.realtimeCoverage == .live })
        #expect(calculation.options.filter { $0.realtimeCoverage == .scheduleOnly }.count == 4)
    }

    @Test func arriveByReturnsFiveProgressivelyEarlierDepartures() async throws {
        let deadline = luxembourgDate(hour: 8, minute: 30)
        let departureMinutes = [30, 40, 50, 60, 70, 80]
        let timetable = makeTimetable(
            routes: departureMinutes.map { makeRoute(id: "R-\($0)", shortName: "\($0)") },
            trips: departureMinutes.map { minute in
                let departureHour = 7 + minute / 60
                let departureMinute = minute % 60
                let arrivalMinuteFromSeven = minute + 10
                return timedTrip(id: "T-\(minute)", routeId: "R-\(minute)", stops: [
                    ("S1", t(departureHour, departureMinute), t(departureHour, departureMinute)),
                    ("S2", t(7 + arrivalMinuteFromSeven / 60, arrivalMinuteFromSeven % 60),
                     t(7 + arrivalMinuteFromSeven / 60, arrivalMinuteFromSeven % 60))
                ])
            }
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 7, minute: 0) }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(deadline)
        )

        #expect(calculation.options.count == 5)
        let departures = calculation.options.compactMap(\.departureTime)
        #expect(zip(departures, departures.dropFirst()).allSatisfy { $0.0 > $0.1 })
        #expect(calculation.options.allSatisfy { ($0.arrivalTime ?? .distantFuture) <= deadline })
    }

    @Test func directBusPublishesWithoutWaitingForRoadProvider() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let roadProvider = SlowRoadRouteProvider()
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: roadProvider,
            now: { now },
            concurrency: .serial
        )

        let calculation = try await completeWithin(seconds: 1) {
            try await routeService.calculateRoute(
                from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
                to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
            )
        }

        #expect(calculation.options.contains { !$0.usesBikeShare })
        #expect(roadProvider.callCount == 0)
    }

    @Test func transitCalculationDoesNotWaitForBikeAvailabilityRefresh() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let bikeService = SlowBikeShareService()
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            bikeShareService: bikeService,
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .serial
        )

        let calculation = try await completeWithin(seconds: 1) {
            try await routeService.calculateRoute(
                from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
                to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
            )
        }

        #expect(!calculation.options.isEmpty)
    }

    @Test func slowATPFeedFallsBackToScheduleOnlyWithinRealtimeBudget() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: SlowATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .serial,
            realtimeBoardBudgetSeconds: 0.05
        )

        let calculation = try await completeWithin(seconds: 5) {
            try await routeService.calculateRoute(
                from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
                to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
                time: .departAt(now),
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh
            )
        }

        #expect(!calculation.options.isEmpty)
        #expect(calculation.options.allSatisfy { $0.realtimeCoverage == .scheduleOnly })
    }

    @Test func initialCalculationUsesScheduleOnlyWithoutRealtimeNetwork() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let atpClient = CountingATPClient()
        let roadProvider = ConcurrencyTrackingRoadRouteProvider()
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: atpClient,
            roadRouteProvider: roadProvider,
            now: { now },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        #expect(atpClient.boardCallCount == 0)
        #expect(roadProvider.callCount == 0)
        #expect(calculation.options.allSatisfy { $0.realtimeCoverage == .scheduleOnly })
    }

    @Test func routeOptionsShowAtMostOneVelohAndKeepTransitAlternatives() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let origin = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let destination = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        let stations = [
            BikeShareStation(
                id: "bike-origin", name: "Origin station", location: origin,
                bikesAvailable: 4, docksAvailable: 4, isOpen: true, lastUpdated: now
            ),
            BikeShareStation(
                id: "bike-destination", name: "Destination station", location: destination,
                bikesAvailable: 4, docksAvailable: 4, isOpen: true, lastUpdated: now
            ),
            BikeShareStation(
                id: "bike-nearby", name: "Nearby station",
                location: LocationPoint(id: "bike-nearby", name: "Nearby station", latitude: 49.605, longitude: 6.105),
                bikesAvailable: 4, docksAvailable: 4, isOpen: true, lastUpdated: now
            )
        ]
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            bikeShareService: MockBikeShareService(stations: stations, fetchedAt: now),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(from: origin, to: destination)

        #expect(calculation.options.allSatisfy { !$0.usesBikeShare })
        #expect(calculation.supplementalOptions.filter(\.usesBikeShare).count <= 1)
        #expect(calculation.options.contains { !$0.usesBikeShare })
    }

    @Test func calculatesDirectGTFSRouteAndEnrichesLiveDelay() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable()
        let atpClient = MockATPClient(departuresByStopId: [
            "S1": [
                Departure(
                    id: "live-15",
                    stopId: "S1",
                    routeId: "R15",
                    lineName: "15",
                    destination: "Central",
                    scheduledDeparture: luxembourgDate(hour: 8, minute: 5),
                    realtimeDeparture: luxembourgDate(hour: 8, minute: 8),
                    delayMinutes: 3,
                    platform: "2",
                    dataSource: .atpOpenAPI
                )
            ]
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: atpClient,
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let transitLeg = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(calculation.plan.dataSource == .gtfs)
        #expect(calculation.options.count == 1)
        #expect(transitLeg.routeName == "15")
        #expect(transitLeg.liveStatus == .delayed)
        #expect(transitLeg.delayMinutes == 3)
        #expect(transitLeg.platform == "2")
        #expect(calculation.mapOverlay?.segments.contains { $0.mode == .bus } == true)
    }

    @Test func realtimeRetimesLeadingWalkAndScheduledTimestamps() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let liveDeparture = luxembourgDate(hour: 8, minute: 8)
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(departuresByStopId: [
                "S1": [Departure(
                    id: "live-15",
                    stopId: "S1",
                    routeId: "R15",
                    lineName: "15",
                    destination: "Central",
                    scheduledDeparture: luxembourgDate(hour: 8, minute: 5),
                    realtimeDeparture: liveDeparture,
                    delayMinutes: 3,
                    dataSource: .atpOpenAPI
                )]
            ]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Door", latitude: 49.599, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let walk = try #require(calculation.plan.legs.first { $0.transportKind == .walking })
        let transit = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(walk.arrivalTime == liveDeparture)
        #expect(walk.scheduledArrivalTime == liveDeparture)
        #expect(walk.departureTime == walk.scheduledDepartureTime)
        #expect(walk.arrivalTime == transit.realtimeDepartureTime)
    }

    @Test func forceRefreshBypassesTheShortLivedRealtimeBoardCache() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let atpClient = CountingATPClient()
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: atpClient,
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )
        let from = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        _ = try await routeService.calculateRoute(
            from: from,
            to: to,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )
        _ = try await routeService.calculateRoute(from: from, to: to)
        #expect(atpClient.boardCallCount == 1)

        _ = try await routeService.calculateRoute(
            from: from,
            to: to,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )
        #expect(atpClient.boardCallCount == 2)
    }

    @Test func realtimeBoardRequestsAreConcurrentButBounded() async throws {
        let atpClient = ConcurrencyTrackingATPClient()
        let engine = PublicTransportRoutingEngine(
            gtfsService: MockGTFSService(timetable: nil),
            atpClient: atpClient,
            bikeShareService: UnavailableBikeShareService(),
            roadRouteProvider: MockRoadRouteProvider(),
            offlineMode: false,
            now: { .now },
            calendar: Calendar(identifier: .gregorian),
            concurrency: RouteCalculationConcurrency(
                cpuWorkerLimit: 1,
                realtimeBoardLimit: 2,
                roadRouteLimit: 1
            ),
            realtimeBoardBudgetSeconds: 10
        )

        let boards = try await engine.departureBoardsByStopId(
            stopIds: Set((0 ..< 7).map { "stop-\($0)" }),
            forceRefresh: true
        )

        #expect(boards.count == 7)
        #expect(atpClient.maximumInFlight == 2)
        #expect(atpClient.maximumInFlight > 1)
    }

    @Test func concurrentRoadRequestsPreserveOptionOrder() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            trips: [
                makeTrip(id: "T15", routeId: "R15", departure: t(8, 5)),
                makeTrip(id: "T16", routeId: "R16", departure: t(8, 15)),
                makeTrip(id: "T17", routeId: "R17", departure: t(8, 25))
            ]
        )
        let roadProvider = ConcurrencyTrackingRoadRouteProvider()
        let service = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: roadProvider,
            now: { now },
            concurrency: RouteCalculationConcurrency(
                cpuWorkerLimit: 4,
                realtimeBoardLimit: 1,
                roadRouteLimit: 2
            )
        )

        let calculation = try await service.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        #expect(calculation.options.count == 3)
        #expect(roadProvider.maximumInFlight <= 2)
        #expect(roadProvider.maximumInFlight > 1)
        #expect(calculation.options.map { $0.plan.legs.first?.tripId } == ["T15", "T16", "T17"])
    }

    @Test func roadRouteCacheIsReusedAcrossCalculations() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let roadProvider = ConcurrencyTrackingRoadRouteProvider()
        let service = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: roadProvider,
            now: { now },
            concurrency: .serial,
            roadGeometryBudgetSeconds: 10
        )
        let from = LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        _ = try await service.calculateRoute(
            from: from,
            to: to,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )
        let firstCalculationCallCount = roadProvider.callCount
        _ = try await service.calculateRoute(
            from: from,
            to: to,
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        #expect(firstCalculationCallCount > 0)
        #expect(roadProvider.callCount == firstCalculationCallCount)
    }

    @Test func serialAndConcurrentCalculationsReturnEquivalentResults() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            trips: [
                makeTrip(id: "T15", routeId: "R15", departure: t(8, 5)),
                makeTrip(id: "T16", routeId: "R16", departure: t(8, 15)),
                makeTrip(id: "T17", routeId: "R17", departure: t(8, 25))
            ]
        )
        let from = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let serial = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .serial
        )
        let concurrent = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now },
            concurrency: .default
        )

        let serialCalculation = try await serial.calculateRoute(from: from, to: to)
        let concurrentCalculation = try await concurrent.calculateRoute(from: from, to: to)

        #expect(serialCalculation.selectedOptionID == concurrentCalculation.selectedOptionID)
        #expect(serialCalculation.options.map(\.id) == concurrentCalculation.options.map(\.id))
        #expect(serialCalculation.options.map(\.plan.legs) == concurrentCalculation.options.map(\.plan.legs))
    }

    @Test func startingANewCalculationCancelsThePreviousOne() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            trips: [
                makeTrip(id: "T15", routeId: "R15", departure: t(8, 5)),
                makeTrip(id: "T16", routeId: "R16", departure: t(8, 15)),
                makeTrip(id: "T17", routeId: "R17", departure: t(8, 25))
            ]
        )
        let roadProvider = CancellationAwareRoadRouteProvider()
        let service = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: roadProvider,
            now: { now },
            concurrency: RouteCalculationConcurrency(
                cpuWorkerLimit: 2,
                realtimeBoardLimit: 1,
                roadRouteLimit: 2
            )
        )
        let from = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let first = Task {
            try await service.calculateRoute(
                from: from,
                to: to,
                time: .leaveNow,
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh
            )
        }
        for _ in 0 ..< 100 where !roadProvider.hasStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(roadProvider.hasStarted)
        let second = Task {
            try await service.calculateRoute(
                from: from,
                to: to,
                time: .leaveNow,
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh
            )
        }

        let firstResult = await first.result
        let secondCalculation = try await second.value

        #expect({
            if case .failure = firstResult { return true }
            return false
        }())
        #expect(!secondCalculation.options.isEmpty)
    }

    @Test func offlineModeIgnoresLiveDelaysAndUsesScheduledTimes() async throws {
        // Offline mode must plan on the static schedule only: even with a delayed live
        // departure available, the leg stays scheduled (no delay/live status).
        let now = luxembourgDate(hour: 8, minute: 0)
        let atpClient = MockATPClient(departuresByStopId: [
            "S1": [
                Departure(
                    id: "live-15",
                    stopId: "S1",
                    routeId: "R15",
                    lineName: "15",
                    destination: "Central",
                    scheduledDeparture: luxembourgDate(hour: 8, minute: 5),
                    realtimeDeparture: luxembourgDate(hour: 8, minute: 8),
                    delayMinutes: 3,
                    platform: "2",
                    dataSource: .atpOpenAPI
                )
            ]
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: atpClient,
            roadRouteProvider: MockRoadRouteProvider(),
            offlineMode: true,
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let transitLeg = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(transitLeg.liveStatus == .scheduled)
        #expect(transitLeg.delayMinutes == nil)
        #expect(transitLeg.departureTime == luxembourgDate(hour: 8, minute: 5))
    }

    @Test func offlineModeEnforcesFifteenMinuteTransferBuffer() async throws {
        // A 3-minute connection is feasible live but must be rejected offline; the engine
        // has to skip it and choose the later trip that clears the 15-minute buffer.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-1", shortName: "1"),
                makeRoute(id: "R-tight", shortName: "T"),
                makeRoute(id: "R-safe", shortName: "S")
            ],
            trips: [
                timedTrip(id: "T-1", routeId: "R-1", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-tight", routeId: "R-tight", stops: [
                    ("S2", t(8, 18), t(8, 18)),
                    ("S3", t(8, 28), t(8, 28))
                ]),
                timedTrip(id: "T-safe", routeId: "R-safe", stops: [
                    ("S2", t(8, 32), t(8, 32)),
                    ("S3", t(8, 42), t(8, 42))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            offlineMode: true,
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12)
        )

        let option = try #require(calculation.options.first)
        let transitLegs = option.transitLegs
        #expect(transitLegs.map(\.routeId) == ["R-1", "R-safe"])
        let arrival = try #require(transitLegs.first?.arrivalTime)
        let nextDeparture = try #require(transitLegs.last?.departureTime)
        #expect(nextDeparture.timeIntervalSince(arrival) >= 15 * 60)
        // The tight 3-minute connection must not appear in any returned option.
        #expect(calculation.options.allSatisfy { option in
            option.plan.legs.allSatisfy { $0.routeId != "R-tight" }
        })
    }

    @Test func omitsWalkingWhenMapKitCannotProduceAnExactRoute() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable()
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        await #expect(throws: RoutingError.noPublicTransportRoute) {
            try await routeService.calculateRoute(
                from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
                to: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1)
            )
        }
    }

    @Test func walkingRouteFallsBackWhenTimetableIsUnavailableAndHonorsPlanningTime() async throws {
        let anchor = luxembourgDate(hour: 9, minute: 0)
        let origin = LocationPoint(name: "Origin", latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(name: "Destination", latitude: 49.61, longitude: 6.11)
        let routeCoordinates = [RouteMapCoordinate(origin), RouteMapCoordinate(destination)]

        for planningTime in [
            RoutePlanningTime.leaveNow,
            .departAt(anchor.addingTimeInterval(600)),
            .arriveBy(anchor.addingTimeInterval(3_600))
        ] {
            let service = PublicTransportRouteService(
                gtfsService: MockGTFSService(timetable: nil),
                atpClient: MockATPClient(),
                roadRouteProvider: MockRoadRouteProvider(routes: [
                    "49.6,6.1|49.61,6.11": routeCoordinates
                ]),
                now: { anchor },
                concurrency: .serial
            )

            let calculation = try await service.calculateRoute(
                from: origin,
                to: destination,
                time: planningTime,
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh
            )
            let walking = try #require(calculation.options.first)
            #expect(calculation.options.count == 1)
            #expect(walking.isWalkingOnly)
            #expect(walking.mapOverlay?.segments.first?.mode == .walking)
            #expect(walking.plan.distanceMeters != nil)

            switch planningTime {
            case .leaveNow:
                #expect(walking.departureTime == anchor)
            case let .departAt(date):
                #expect(walking.departureTime == date)
            case let .arriveBy(date):
                #expect(walking.arrivalTime == date)
            }
        }
    }

    @Test func walkingComparisonUsesDurationThenArrivalAndCapsPrimaryCards() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let origin = LocationPoint(name: "Origin", latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(name: "Destination", latitude: 49.61, longitude: 6.11)
        let engine = PublicTransportRoutingEngine(
            gtfsService: MockGTFSService(timetable: nil),
            atpClient: MockATPClient(),
            bikeShareService: UnavailableBikeShareService(),
            roadRouteProvider: MockRoadRouteProvider(),
            offlineMode: false,
            now: { anchor },
            calendar: Calendar(identifier: .gregorian),
            concurrency: .serial
        )

        func option(
            id: String,
            walking: Bool,
            departure: TimeInterval,
            duration: TimeInterval
        ) -> RouteOption {
            let start = Date(timeIntervalSince1970: departure)
            let end = start.addingTimeInterval(duration)
            let kind: RouteLegTransportKind = walking ? .walking : .transit
            let leg = RoutePlan.Leg(
                id: "\(id)-leg",
                mode: walking ? .walking : .bus,
                transportKind: kind,
                routeName: walking ? nil : id,
                origin: origin,
                destination: destination,
                departureTime: start,
                arrivalTime: end,
                distanceMeters: 1_000
            )
            return RouteOption(
                id: id,
                plan: RoutePlan(
                    id: id,
                    origin: origin,
                    destination: destination,
                    expectedTravelTime: duration,
                    distanceMeters: 1_000,
                    legs: [leg],
                    dataSource: .mock
                ),
                mapOverlay: nil
            )
        }

        let shortWalk = option(id: "walk-short", walking: true, departure: 1_000, duration: 300)
        let slowerTransit = option(id: "transit-slow", walking: false, departure: 1_100, duration: 600)
        #expect(engine.resolvedPrimaryOptions(
            walking: shortWalk,
            transit: [slowerTransit],
            limit: 5
        ) == [shortWalk])

        let longWalk = option(id: "walk-long", walking: true, departure: 1_000, duration: 600)
        let waitingTransit = (0 ..< 5).map { index in
            option(
                id: "transit-\(index)",
                walking: false,
                departure: 1_700 + Double(index * 60),
                duration: 300
            )
        }
        let combined = engine.resolvedPrimaryOptions(
            walking: longWalk,
            transit: waitingTransit,
            limit: 5
        )
        #expect(combined.first == longWalk)
        #expect(combined.count == 5)
        #expect(combined.dropFirst() == waitingTransit.prefix(4))

        let earlyTransit = option(id: "transit-early", walking: false, departure: 1_100, duration: 300)
        #expect(engine.resolvedPrimaryOptions(
            walking: longWalk,
            transit: [earlyTransit],
            limit: 5
        ) == [earlyTransit])

        let equalDurationTransit = option(
            id: "transit-equal",
            walking: false,
            departure: 1_400,
            duration: 600
        )
        #expect(engine.resolvedPrimaryOptions(
            walking: longWalk,
            transit: [equalDurationTransit],
            limit: 5
        ) == [equalDurationTransit])
    }

    @Test func cancelledEarlierTripIsDemotedBehindLiveFeasibleTrip() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let trips = [
            makeTrip(id: "T15-cancelled", routeId: "R15", departure: 8 * 3600 + 5 * 60),
            makeTrip(id: "T16-live", routeId: "R16", departure: 8 * 3600 + 10 * 60)
        ]
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R15", shortName: "15"),
                makeRoute(id: "R16", shortName: "16")
            ],
            trips: trips
        )
        let atpClient = MockATPClient(departuresByStopId: [
            "S1": [
                Departure(
                    id: "cancelled-15",
                    stopId: "S1",
                    routeId: "R15",
                    lineName: "15",
                    destination: "Central",
                    scheduledDeparture: luxembourgDate(hour: 8, minute: 5),
                    isCancelled: true,
                    dataSource: .atpOpenAPI
                ),
                Departure(
                    id: "live-16",
                    stopId: "S1",
                    routeId: "R16",
                    lineName: "16",
                    destination: "Central",
                    scheduledDeparture: luxembourgDate(hour: 8, minute: 10),
                    realtimeDeparture: luxembourgDate(hour: 8, minute: 10),
                    delayMinutes: 0,
                    dataSource: .atpOpenAPI
                )
            ]
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: atpClient,
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let transitLeg = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(transitLeg.routeId == "R16")
        #expect(transitLeg.liveStatus == .live)
    }

    @Test func returnsMultipleRouteOptionsWhenSeveralTripsAreAvailable() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(trips: [
            makeTrip(id: "T15", routeId: "R15", departure: 8 * 3600 + 5 * 60),
            makeTrip(id: "T16", routeId: "R16", departure: 8 * 3600 + 15 * 60),
            makeTrip(id: "T17", routeId: "R17", departure: 8 * 3600 + 25 * 60)
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        #expect(calculation.options.count == 3)
        #expect(calculation.options.map(\.plan.legs).allSatisfy { legs in
            legs.contains(where: { $0.transportKind == .transit })
        })
    }

    @Test func fastestRouteUsesEarliestDestinationArrivalOverTransferComfort() async throws {
        // Direct trip arrives 8:25; a 1-transfer itinerary arrives 8:23. The
        // Fastest tab must use destination arrival rather than an implicit transfer
        // penalty. The earlier direct trip is not a fallback after missing the
        // later, faster departure opportunity.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R15", shortName: "15"),
                makeRoute(id: "R16", shortName: "16"),
                makeRoute(id: "R17", shortName: "17")
            ],
            trips: [
                timedTrip(id: "Tdirect", routeId: "R15", stops: [
                    ("S1", t(8, 1), t(8, 1)),
                    ("S2", t(8, 25), t(8, 25))
                ]),
                timedTrip(id: "Tleg1", routeId: "R16", stops: [
                    ("S1", t(8, 2), t(8, 2)),
                    ("S3", t(8, 11), t(8, 11))
                ]),
                timedTrip(id: "Tleg2", routeId: "R17", stops: [
                    ("S3", t(8, 14), t(8, 14)),
                    ("S2", t(8, 23), t(8, 23))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let first = try #require(calculation.options.first)
        #expect(first.transferCount == 1)
        #expect(first.plan.legs.first { $0.transportKind == .transit }?.routeId == "R16")
        #expect(calculation.options.allSatisfy { $0.transferCount > 0 })
    }

    @Test func dropsJourneyDominatedOnEveryAxis() async throws {
        // Bad itinerary leaves earlier (8:01) but arrives later (8:30) with an extra
        // transfer — strictly worse than the direct 8:05→8:21 trip, so it is pruned.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R15", shortName: "15"),
                makeRoute(id: "R16", shortName: "16"),
                makeRoute(id: "R17", shortName: "17")
            ],
            trips: [
                timedTrip(id: "Tgood", routeId: "R15", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 21), t(8, 21))
                ]),
                timedTrip(id: "Tbad1", routeId: "R16", stops: [
                    ("S1", t(8, 1), t(8, 1)),
                    ("S3", t(8, 10), t(8, 10))
                ]),
                timedTrip(id: "Tbad2", routeId: "R17", stops: [
                    ("S3", t(8, 12), t(8, 12)),
                    ("S2", t(8, 30), t(8, 30))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        #expect(calculation.options.allSatisfy { $0.transferCount == 0 })
        #expect(calculation.options.allSatisfy { option in
            option.plan.legs.allSatisfy { $0.routeId != "R17" }
        })
    }

    @Test func cachedRoutingContextKeepsRequestTimeFresh() async throws {
        var currentNow = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(trips: [
            makeTrip(id: "T15", routeId: "R15", departure: 8 * 3600 + 5 * 60),
            makeTrip(id: "T16", routeId: "R16", departure: 8 * 3600 + 30 * 60)
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { currentNow }
        )
        let origin = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let destination = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let firstCalculation = try await routeService.calculateRoute(from: origin, to: destination)
        currentNow = luxembourgDate(hour: 8, minute: 20)
        let secondCalculation = try await routeService.calculateRoute(from: origin, to: destination)

        #expect(firstCalculation.plan.legs.first { $0.transportKind == .transit }?.tripId == "T15")
        #expect(secondCalculation.plan.legs.first { $0.transportKind == .transit }?.tripId == "T16")
    }

    @Test func busRouteOverlayUsesRoadCoordinatesBetweenStops() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let roadRouteProvider = MockRoadRouteProvider(routes: [
            "49.6,6.1|49.61,6.11": [
                RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
                RouteMapCoordinate(latitude: 49.605, longitude: 6.115),
                RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
            ]
        ])
        let expectedCoordinates = roadRouteProvider.routes["49.6,6.1|49.61,6.11"] ?? []
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: roadRouteProvider,
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let busSegment = try #require(calculation.mapOverlay?.segments.first { $0.mode == .bus })
        #expect(busSegment.coordinates == expectedCoordinates)
    }

    @Test func nonBusRouteOverlayKeepsGTFSStopCoordinates() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let roadRouteProvider = MockRoadRouteProvider(routes: [
            "49.6,6.1|49.61,6.11": [
                RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
                RouteMapCoordinate(latitude: 49.605, longitude: 6.115),
                RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
            ]
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable(routes: [
                makeRoute(id: "R15", shortName: "T1", mode: "tram")
            ])),
            atpClient: MockATPClient(),
            roadRouteProvider: roadRouteProvider,
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let tramSegment = try #require(calculation.mapOverlay?.segments.first { $0.mode == .tram })
        #expect(tramSegment.coordinates == [
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
        ])
    }

    @Test func routeWithMultipleBusLegsRoadRoutesEveryBusSegment() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let firstBusCoordinates = [
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
            RouteMapCoordinate(latitude: 49.605, longitude: 6.115),
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
        ]
        let secondBusCoordinates = [
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11),
            RouteMapCoordinate(latitude: 49.615, longitude: 6.125),
            RouteMapCoordinate(latitude: 49.62, longitude: 6.12)
        ]
        let roadRouteProvider = MockRoadRouteProvider(routes: [
            "49.6,6.1|49.61,6.11": firstBusCoordinates,
            "49.61,6.11|49.62,6.12": secondBusCoordinates
        ])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable(
                routes: [
                    makeRoute(id: "R15", shortName: "15"),
                    makeRoute(id: "R16", shortName: "16")
                ],
                trips: [
                    makeTrip(
                        id: "T15",
                        routeId: "R15",
                        departure: 8 * 3600 + 5 * 60,
                        stopIds: ["S1", "S2"]
                    ),
                    makeTrip(
                        id: "T16",
                        routeId: "R16",
                        departure: 8 * 3600 + 30 * 60,
                        stopIds: ["S2", "S3"]
                    )
                ]
            )),
            atpClient: MockATPClient(),
            roadRouteProvider: roadRouteProvider,
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let busSegments = calculation.mapOverlay?.segments.filter { $0.mode == .bus } ?? []
        #expect(busSegments.count == 2)
        #expect(busSegments.map(\.coordinates) == [firstBusCoordinates, secondBusCoordinates])
    }

    @Test func busRouteOverlayKeepsGTFSShapeWhenAvailable() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let mapKitFallbackCoordinates = [
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
            RouteMapCoordinate(latitude: 49.7, longitude: 6.2),
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
        ]
        let shapeCoordinates = [
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
            RouteMapCoordinate(latitude: 49.602, longitude: 6.104),
            RouteMapCoordinate(latitude: 49.606, longitude: 6.108),
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
        ]
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable(
                trips: [
                    makeTrip(
                        id: "T15",
                        routeId: "R15",
                        departure: 8 * 3600 + 5 * 60,
                        shapeId: "shape-15",
                        shapeDistances: [0, 3]
                    )
                ],
                shapes: [
                    GTFSTimetableShapeEntry(
                        id: "shape-15",
                        points: [
                            GTFSTimetableShapePoint(
                                latitude: 49.602,
                                longitude: 6.104,
                                sequence: 1,
                                distanceTraveled: 1
                            ),
                            GTFSTimetableShapePoint(
                                latitude: 49.606,
                                longitude: 6.108,
                                sequence: 2,
                                distanceTraveled: 2
                            )
                        ]
                    )
                ]
            )),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(routes: [
                "49.6,6.1|49.61,6.11": mapKitFallbackCoordinates
            ]),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let busSegment = try #require(calculation.mapOverlay?.segments.first { $0.mode == .bus })
        #expect(busSegment.coordinates == shapeCoordinates)
    }

    @Test func busRouteOverlayRejectsExcessiveMapKitDetour() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(routes: [
                "49.6,6.1|49.61,6.11": [
                    RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
                    RouteMapCoordinate(latitude: 50.0, longitude: 6.6),
                    RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
                ]
            ]),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let busSegment = try #require(calculation.mapOverlay?.segments.first { $0.mode == .bus })
        #expect(busSegment.coordinates == [
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1),
            RouteMapCoordinate(latitude: 49.61, longitude: 6.11)
        ])
    }

    @Test func walkingUsesRoadDistanceWhenChoosingAndTimingAConnection() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let origin = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let roadCoordinates = [
            RouteMapCoordinate(origin),
            RouteMapCoordinate(latitude: 49.6015, longitude: 6.1015),
            RouteMapCoordinate(latitude: 49.5985, longitude: 6.0985),
            RouteMapCoordinate(latitude: 49.6, longitude: 6.1)
        ]
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-early", shortName: "E"),
                makeRoute(id: "R-late", shortName: "L")
            ],
            trips: [
                timedTrip(id: "T-early", routeId: "R-early", stops: [
                    ("S1", t(8, 2), t(8, 2)),
                    ("S2", t(8, 20), t(8, 20))
                ]),
                timedTrip(id: "T-late", routeId: "R-late", stops: [
                    ("S1", t(8, 10), t(8, 10)),
                    ("S2", t(8, 28), t(8, 28))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(routes: [
                "49.6001,6.1001|49.6,6.1": roadCoordinates
            ]),
            now: { now },
            concurrency: .serial
        )

        let calculation = try await routeService.calculateRoute(
            from: origin,
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .departAt(now),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let first = try #require(calculation.options.first)
        let walk = try #require(first.plan.legs.first { $0.transportKind == .walking })
        #expect(first.transitLegs.first?.routeId == "R-late")
        #expect((walk.distanceMeters ?? 0) > 400)
        #expect(walk.arrivalTime?.timeIntervalSince(walk.departureTime ?? .distantPast)
            == Double(ceil((walk.distanceMeters ?? 0) / 1.33)))
    }

    private func makeTimetable(
        routes: [GTFSTimetableRouteEntry]? = nil,
        trips: [GTFSTimetableTripEntry]? = nil,
        transfers: [GTFSTimetableTransferEntry] = [],
        shapes: [GTFSTimetableShapeEntry] = [],
        services: [GTFSTimetableServiceEntry]? = nil
    ) -> GTFSTimetableIndexPayload {
        GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1",
                    name: "Hill Lift",
                    latitude: 49.6,
                    longitude: 6.1,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S2",
                    name: "Central",
                    latitude: 49.61,
                    longitude: 6.11,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S3",
                    name: "Airport",
                    latitude: 49.62,
                    longitude: 6.12,
                    parentStation: nil,
                    platformCode: nil
                )
            ],
            routes: routes ?? [
                makeRoute(id: "R15", shortName: "15"),
                makeRoute(id: "R16", shortName: "16"),
                makeRoute(id: "R17", shortName: "17")
            ],
            services: services ?? [
                GTFSTimetableServiceEntry(
                    id: "WEEK",
                    weekdays: [],
                    startDate: nil,
                    endDate: nil,
                    addedDates: ["20260614"],
                    removedDates: []
                )
            ],
            trips: trips ?? [makeTrip(id: "T15", routeId: "R15", departure: 8 * 3600 + 5 * 60)],
            transfers: transfers,
            shapes: shapes
        )
    }

    private func makeMobiliteitStyleTimetable() -> GTFSTimetableIndexPayload {
        let stops = [
            GTFSTimetableStopEntry(
                id: "senningerberg-gromscheed", name: "Senningerberg, Gromscheed",
                latitude: 49.65, longitude: 6.22, parentStation: nil, platformCode: nil
            ),
            GTFSTimetableStopEntry(
                id: "charlys-statioun", name: "Senningerberg, Charlys Statioun",
                latitude: 49.635, longitude: 6.18, parentStation: nil, platformCode: nil
            ),
            GTFSTimetableStopEntry(
                id: "hamilius-interchange", name: "Hamilius interchange",
                latitude: 49.615, longitude: 6.145, parentStation: nil, platformCode: nil
            ),
            GTFSTimetableStopEntry(
                id: "hamilius-bus", name: "Hamilius",
                latitude: 49.61, longitude: 6.13, parentStation: nil, platformCode: nil
            )
        ]
        let routes = [
            makeRoute(id: "R326", shortName: "326"),
            makeRoute(id: "RT1", shortName: "T1", mode: "tram"),
            makeRoute(id: "R212", shortName: "212"),
            makeRoute(id: "R21", shortName: "21"),
            makeRoute(id: "R850", shortName: "850"),
            makeRoute(id: "R4", shortName: "4"),
            makeRoute(id: "R29", shortName: "29"),
            makeRoute(id: "R18", shortName: "18"),
            makeRoute(id: "R9", shortName: "9")
        ]
        let trips = [
            timedTrip(id: "T-326", routeId: "R326", stops: [
                ("senningerberg-gromscheed", t(21, 35), t(21, 35)),
                ("charlys-statioun", t(21, 50), t(21, 50))
            ]),
            timedTrip(id: "T-T1-direct", routeId: "RT1", stops: [
                ("charlys-statioun", t(21, 53), t(21, 53)),
                ("hamilius-bus", t(22, 10), t(22, 10))
            ]),
            timedTrip(id: "T-212", routeId: "R212", stops: [
                ("senningerberg-gromscheed", t(21, 55), t(21, 55)),
                ("charlys-statioun", t(22, 5), t(22, 5))
            ]),
            timedTrip(id: "T-21", routeId: "R21", stops: [
                ("charlys-statioun", t(22, 8), t(22, 8)),
                ("hamilius-bus", t(22, 20), t(22, 20))
            ]),
            timedTrip(id: "T-850", routeId: "R850", stops: [
                ("senningerberg-gromscheed", t(21, 58), t(21, 58)),
                ("charlys-statioun", t(22, 8), t(22, 8))
            ]),
            timedTrip(id: "T-4", routeId: "R4", stops: [
                ("charlys-statioun", t(22, 11), t(22, 11)),
                ("hamilius-bus", t(22, 24), t(22, 24))
            ]),
            timedTrip(id: "T-29", routeId: "R29", stops: [
                ("senningerberg-gromscheed", t(22, 0), t(22, 0)),
                ("charlys-statioun", t(22, 10), t(22, 10))
            ]),
            timedTrip(id: "T-T1-transfer", routeId: "RT1", stops: [
                ("charlys-statioun", t(22, 13), t(22, 13)),
                ("hamilius-interchange", t(22, 23), t(22, 23))
            ]),
            timedTrip(id: "T-18", routeId: "R18", stops: [
                ("hamilius-interchange", t(22, 26), t(22, 26)),
                ("hamilius-bus", t(22, 38), t(22, 38))
            ]),
            timedTrip(id: "T-9", routeId: "R9", stops: [
                ("charlys-statioun", t(22, 13), t(22, 13)),
                ("hamilius-bus", t(22, 30), t(22, 30))
            ])
        ]
        return GTFSTimetableIndexPayload(
            source: "mobiliteit-scenario",
            stops: stops,
            routes: routes,
            services: [GTFSTimetableServiceEntry(
                id: "WEEK", weekdays: [], startDate: nil, endDate: nil,
                addedDates: ["20260614"], removedDates: []
            )],
            trips: trips,
            transfers: [],
            shapes: []
        )
    }

    private func makeRoute(id: String, shortName: String, mode: String = "bus") -> GTFSTimetableRouteEntry {
        GTFSTimetableRouteEntry(
            id: id,
            shortName: shortName,
            longName: nil,
            mode: mode,
            operatorName: "Operator"
        )
    }

    private func makeTrip(
        id: String,
        routeId: String,
        departure: Int,
        stopIds: [String] = ["S1", "S2"],
        shapeId: String? = nil,
        shapeDistances: [Double?]? = nil
    ) -> GTFSTimetableTripEntry {
        GTFSTimetableTripEntry(
            id: id,
            routeId: routeId,
            serviceId: "WEEK",
            headsign: "Central",
            directionId: nil,
            shapeId: shapeId,
            stopTimes: stopIds.enumerated().map { offset, stopId in
                GTFSTimetableStopTimeEntry(
                    stopId: stopId,
                    arrivalSeconds: departure + offset * 20 * 60,
                    departureSeconds: departure + offset * 20 * 60,
                    sequence: offset + 1,
                    headsign: nil,
                    pickupType: nil,
                    dropOffType: nil,
                    shapeDistanceTraveled: shapeDistances?[offset] ?? nil
                )
            }
        )
    }

    /// Seconds from service start (midnight) for a given wall-clock time.
    private func t(_ hour: Int, _ minute: Int) -> Int {
        hour * 3600 + minute * 60
    }

    /// Builds a trip with explicit per-stop arrival/departure seconds, for tests that
    /// need finer timing than `makeTrip`'s fixed 20-minute spacing.
    private func timedTrip(
        id: String,
        routeId: String,
        stops: [(stopId: String, arrival: Int, departure: Int)]
    ) -> GTFSTimetableTripEntry {
        GTFSTimetableTripEntry(
            id: id,
            routeId: routeId,
            serviceId: "WEEK",
            headsign: "Central",
            directionId: nil,
            shapeId: nil,
            stopTimes: stops.enumerated().map { offset, stop in
                GTFSTimetableStopTimeEntry(
                    stopId: stop.stopId,
                    arrivalSeconds: stop.arrival,
                    departureSeconds: stop.departure,
                    sequence: offset + 1,
                    headsign: nil,
                    pickupType: nil,
                    dropOffType: nil,
                    shapeDistanceTraveled: nil
                )
            }
        )
    }

    @Test func planForDepartAtAndArriveBy() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )
        let from = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let departAt = try await routeService.calculateRoute(
            from: from, to: to, time: .departAt(luxembourgDate(hour: 8, minute: 0))
        )
        #expect(!departAt.options.isEmpty)

        let arriveBy = try await routeService.calculateRoute(
            from: from, to: to, time: .arriveBy(luxembourgDate(hour: 8, minute: 30))
        )
        #expect(!arriveBy.options.isEmpty)
    }

    @Test func arriveBySchedulesDirectBikeShareBackwardsFromDeadline() async throws {
        let deadline = luxembourgDate(hour: 8, minute: 30)
        let origin = LocationPoint(name: "Bike origin", latitude: 49.600, longitude: 6.100)
        let destination = LocationPoint(name: "Bike destination", latitude: 49.610, longitude: 6.110)
        let stations = [
            BikeShareStation(
                id: "bike-origin",
                name: "Origin station",
                location: origin,
                bikesAvailable: 4,
                docksAvailable: 4,
                isOpen: true,
                lastUpdated: deadline
            ),
            BikeShareStation(
                id: "bike-destination",
                name: "Destination station",
                location: destination,
                bikesAvailable: 4,
                docksAvailable: 4,
                isOpen: true,
                lastUpdated: deadline
            )
        ]
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: makeTimetable()),
            atpClient: MockATPClient(),
            bikeShareService: MockBikeShareService(stations: stations, fetchedAt: deadline),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 8, minute: 0) }
        )

        let calculation = try await routeService.calculateRoute(
            from: origin,
            to: destination,
            time: .arriveBy(deadline)
        )

        let bikeOption = try #require(calculation.supplementalOptions.first { option in
            option.plan.legs.contains { $0.transportKind == .bikeShare }
        })
        #expect(bikeOption.arrivalTime == deadline)
        let departure = try #require(bikeOption.departureTime)
        #expect(departure < deadline)
        #expect(bikeOption.plan.expectedTravelTime == deadline.timeIntervalSince(departure))
    }

    @Test func skipsNoPickupTripButStillBoardsLaterTrip() async throws {
        // A1: the earlier trip forbids boarding at S1 (pickup_type = 1). The scan must skip
        // it and still board the later trip rather than breaking out of the stop entirely.
        let now = luxembourgDate(hour: 8, minute: 0)
        let earlyNoPickup = GTFSTimetableTripEntry(
            id: "T-early", routeId: "R15", serviceId: "WEEK", headsign: "Central",
            directionId: nil, shapeId: nil,
            stopTimes: [
                GTFSTimetableStopTimeEntry(
                    stopId: "S1", arrivalSeconds: t(8, 5), departureSeconds: t(8, 5),
                    sequence: 1, headsign: nil, pickupType: "1", dropOffType: nil,
                    shapeDistanceTraveled: nil
                ),
                GTFSTimetableStopTimeEntry(
                    stopId: "S2", arrivalSeconds: t(8, 20), departureSeconds: t(8, 20),
                    sequence: 2, headsign: nil, pickupType: nil, dropOffType: nil,
                    shapeDistanceTraveled: nil
                )
            ]
        )
        let timetable = makeTimetable(
            routes: [makeRoute(id: "R15", shortName: "15"), makeRoute(id: "R16", shortName: "16")],
            trips: [earlyNoPickup, makeTrip(id: "T-late", routeId: "R16", departure: t(8, 10))]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let transitLeg = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(transitLeg.routeId == "R16")
    }

    @Test func arriveByPrefersLatestDepartureWithHonestTravelTime() async throws {
        // A2/A3: both trips arrive before 8:30; the later-departing one should rank first,
        // and its travel time is the real 15-min ride — not the ~3h arrive-by anchor window.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [makeRoute(id: "R-early", shortName: "E"), makeRoute(id: "R-late", shortName: "L")],
            trips: [
                timedTrip(id: "T-early", routeId: "R-early", stops: [
                    ("S1", t(8, 0), t(8, 0)),
                    ("S2", t(8, 20), t(8, 20))
                ]),
                timedTrip(id: "T-late", routeId: "R-late", stops: [
                    ("S1", t(8, 10), t(8, 10)),
                    ("S2", t(8, 25), t(8, 25))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(luxembourgDate(hour: 8, minute: 30))
        )

        let first = try #require(calculation.options.first)
        #expect(first.plan.legs.first { $0.transportKind == .transit }?.routeId == "R-late")
        let travelTime = try #require(first.plan.expectedTravelTime)
        #expect(travelTime == Double(15 * 60))
        #expect(calculation.options.contains { option in
            option.plan.legs.contains { $0.routeId == "R-early" }
        })
    }

    @Test func arriveByReverseSearchKeepsLaterConnectingJourney() async throws {
        // Regression for the old `deadline - 3h` forward anchor: the early arrival at
        // S2 used to prune the later connection before arrive-by ranking could see it.
        let deadline = luxembourgDate(hour: 18, minute: 50)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-early-1", shortName: "E1"),
                makeRoute(id: "R-early-2", shortName: "E2"),
                makeRoute(id: "R-late-1", shortName: "L1"),
                makeRoute(id: "R-late-2", shortName: "L2")
            ],
            trips: [
                timedTrip(id: "T-early-1", routeId: "R-early-1", stops: [
                    ("S1", t(16, 0), t(16, 0)),
                    ("S2", t(16, 10), t(16, 10))
                ]),
                timedTrip(id: "T-early-2", routeId: "R-early-2", stops: [
                    ("S2", t(16, 15), t(16, 15)),
                    ("S3", t(16, 30), t(16, 30))
                ]),
                timedTrip(id: "T-late-1", routeId: "R-late-1", stops: [
                    ("S1", t(17, 40), t(17, 40)),
                    ("S2", t(18, 5), t(18, 5))
                ]),
                timedTrip(id: "T-late-2", routeId: "R-late-2", stops: [
                    ("S2", t(18, 10), t(18, 10)),
                    ("S3", t(18, 40), t(18, 40))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 15, minute: 0) }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12),
            time: .arriveBy(deadline)
        )

        let selected = try #require(calculation.options.first)
        #expect(selected.transitLegs.map(\.routeId) == ["R-late-1", "R-late-2"])
        #expect(selected.departureTime == luxembourgDate(hour: 17, minute: 40))
        #expect(selected.arrivalTime == luxembourgDate(hour: 18, minute: 40))
        #expect(selected.arrivalTime.map { $0 <= deadline } == true)
    }

    @Test func arriveByRanksRealtimeOnTimeRouteAheadOfLaterDelayedRoute() async throws {
        let deadline = luxembourgDate(hour: 8, minute: 30)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-on-time", shortName: "O"),
                makeRoute(id: "R-delayed", shortName: "D")
            ],
            trips: [
                timedTrip(id: "T-on-time", routeId: "R-on-time", stops: [
                    ("S1", t(8, 0), t(8, 0)),
                    ("S2", t(8, 28), t(8, 28))
                ]),
                timedTrip(id: "T-delayed", routeId: "R-delayed", stops: [
                    ("S1", t(8, 10), t(8, 10)),
                    ("S2", t(8, 25), t(8, 25))
                ])
            ]
        )
        let delayedDeparture = Departure(
            id: "live-delayed",
            stopId: "S1",
            routeId: "R-delayed",
            lineName: "D",
            destination: "Central",
            scheduledDeparture: luxembourgDate(hour: 8, minute: 10),
            realtimeDeparture: luxembourgDate(hour: 8, minute: 20),
            delayMinutes: 10,
            dataSource: .atpOpenAPI
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(departuresByStopId: ["S1": [delayedDeparture]]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 8, minute: 0) }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(deadline),
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-on-time")
        #expect(calculation.options.allSatisfy { ($0.arrivalTime ?? .distantFuture) <= deadline })
        #expect(calculation.options.allSatisfy {
            $0.transitLegs.first?.routeId != "R-delayed"
        })
    }

    @Test func arriveByRanksLeastLateRouteWhenEveryLiveOptionMissesDeadline() async throws {
        let deadline = luxembourgDate(hour: 8, minute: 30)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-less-late", shortName: "A"),
                makeRoute(id: "R-more-late", shortName: "B")
            ],
            trips: [
                timedTrip(id: "T-less-late", routeId: "R-less-late", stops: [
                    ("S1", t(8, 10), t(8, 10)),
                    ("S2", t(8, 25), t(8, 25))
                ]),
                timedTrip(id: "T-more-late", routeId: "R-more-late", stops: [
                    ("S1", t(8, 12), t(8, 12)),
                    ("S2", t(8, 28), t(8, 28))
                ])
            ]
        )
        let liveDepartures = [
            Departure(
                id: "less-late", stopId: "S1", routeId: "R-less-late", lineName: "A",
                destination: "Central", scheduledDeparture: luxembourgDate(hour: 8, minute: 10),
                realtimeDeparture: luxembourgDate(hour: 8, minute: 20), delayMinutes: 10,
                dataSource: .atpOpenAPI
            ),
            Departure(
                id: "more-late", stopId: "S1", routeId: "R-more-late", lineName: "B",
                destination: "Central", scheduledDeparture: luxembourgDate(hour: 8, minute: 12),
                realtimeDeparture: luxembourgDate(hour: 8, minute: 32), delayMinutes: 20,
                dataSource: .atpOpenAPI
            )
        ]
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(departuresByStopId: ["S1": liveDepartures]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 8, minute: 0) }
        )

        do {
            _ = try await routeService.calculateRoute(
                from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
                to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
                time: .arriveBy(deadline),
                filters: RoutePlannerFilters(),
                realtimeRefreshPolicy: .forceRefresh
            )
            Issue.record("Expected no route when every live journey misses the deadline")
        } catch {
            #expect(error as? RoutingError == .noPublicTransportRoute)
        }
    }

    @Test func chainedFootTransfersBecomeOnePhysicalWalkWithOneBuffer() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "O", name: "Origin", latitude: 49.600, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "A", name: "Transfer A", latitude: 49.610, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "B", name: "Transfer B", latitude: 49.611, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "C", name: "Transfer C", latitude: 49.612, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "D", name: "Destination", latitude: 49.622, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                )
            ],
            routes: [makeRoute(id: "R-1", shortName: "1"), makeRoute(id: "R-2", shortName: "2")],
            services: [GTFSTimetableServiceEntry(
                id: "WEEK", weekdays: [], startDate: nil, endDate: nil,
                addedDates: ["20260614"], removedDates: []
            )],
            trips: [
                timedTrip(id: "T-1", routeId: "R-1", stops: [
                    ("O", t(8, 5), t(8, 5)),
                    ("A", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-2", routeId: "R-2", stops: [
                    ("C", t(8, 20), t(8, 20)),
                    ("D", t(8, 35), t(8, 35))
                ])
            ],
            transfers: [],
            shapes: []
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "O", name: "Origin", latitude: 49.600, longitude: 6.100),
            to: LocationPoint(id: "D", name: "Destination", latitude: 49.622, longitude: 6.100)
        )

        let option = try #require(calculation.options.first)
        #expect(option.transitLegs.map(\.routeId) == ["R-1", "R-2"])
        #expect(zip(option.plan.legs, option.plan.legs.dropFirst()).allSatisfy { pair in
            (pair.0.transportKind == .walking && pair.1.transportKind == .walking) == false
        })
        let walk = try #require(option.plan.legs.first { $0.transportKind == .walking })
        #expect((210.0 ... 235.0).contains(walk.distanceMeters ?? 0))
        let walkStart = try #require(walk.scheduledDepartureTime)
        let walkEnd = try #require(walk.scheduledArrivalTime)
        #expect((160 ... 180).contains(Int(walkEnd.timeIntervalSince(walkStart))))
        let secondDeparture = try #require(option.transitLegs.last?.scheduledDepartureTime)
        #expect((120 ... 150).contains(Int(secondDeparture.timeIntervalSince(walkEnd))))
    }

    @Test func arriveByRespectsSameStopGTFSMinimumTransferTime() async throws {
        let deadline = luxembourgDate(hour: 8, minute: 45)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-in", shortName: "I"),
                makeRoute(id: "R-tight", shortName: "T"),
                makeRoute(id: "R-safe", shortName: "S")
            ],
            trips: [
                timedTrip(id: "T-in", routeId: "R-in", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-tight", routeId: "R-tight", stops: [
                    ("S2", t(8, 20), t(8, 20)),
                    ("S3", t(8, 30), t(8, 30))
                ]),
                timedTrip(id: "T-safe", routeId: "R-safe", stops: [
                    ("S2", t(8, 26), t(8, 26)),
                    ("S3", t(8, 40), t(8, 40))
                ])
            ],
            transfers: [GTFSTimetableTransferEntry(
                fromStopId: "S2",
                toStopId: "S2",
                minimumTransferSeconds: 10 * 60
            )]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { luxembourgDate(hour: 8, minute: 0) }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12),
            time: .arriveBy(deadline)
        )

        #expect(calculation.options.first?.transitLegs.map(\.routeId) == ["R-in", "R-safe"])
        #expect(calculation.options.allSatisfy { option in
            option.transitLegs.contains { $0.routeId == "R-tight" } == false
        })
    }

    @Test func realtimeBrokenWalkingConnectionWarnsBoardingLegAndIsDemoted() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1", name: "Origin", latitude: 49.600, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "A", name: "Transfer A", latitude: 49.6100, longitude: 6.110,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "B", name: "Transfer B", latitude: 49.6105, longitude: 6.110,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S3", name: "Destination", latitude: 49.620, longitude: 6.120,
                    parentStation: nil, platformCode: nil
                )
            ],
            routes: [
                makeRoute(id: "R-in", shortName: "I"),
                makeRoute(id: "R-next", shortName: "N"),
                makeRoute(id: "R-direct", shortName: "D")
            ],
            services: [GTFSTimetableServiceEntry(
                id: "WEEK", weekdays: [], startDate: nil, endDate: nil,
                addedDates: ["20260614"], removedDates: []
            )],
            trips: [
                timedTrip(id: "T-in", routeId: "R-in", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("A", t(8, 10), t(8, 10))
                ]),
                timedTrip(id: "T-next", routeId: "R-next", stops: [
                    ("B", t(8, 15), t(8, 15)),
                    ("S3", t(8, 25), t(8, 25))
                ]),
                timedTrip(id: "T-direct", routeId: "R-direct", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S3", t(8, 30), t(8, 30))
                ])
            ],
            transfers: [],
            shapes: []
        )
        let delayedIncoming = Departure(
            id: "live-in",
            stopId: "S1",
            routeId: "R-in",
            lineName: "I",
            destination: "Transfer A",
            scheduledDeparture: luxembourgDate(hour: 8, minute: 5),
            realtimeDeparture: luxembourgDate(hour: 8, minute: 11),
            delayMinutes: 6,
            dataSource: .atpOpenAPI
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(departuresByStopId: ["S1": [delayedIncoming]]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Origin", latitude: 49.600, longitude: 6.100),
            to: LocationPoint(id: "S3", name: "Destination", latitude: 49.620, longitude: 6.120),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-direct")
        #expect(calculation.options.allSatisfy { option in
            option.transitLegs.map(\.routeId) != ["R-in", "R-next"]
        })
    }

    @Test func tightTransferWarningAppliesOnlyThroughTwoMinutes() async throws {
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-in", shortName: "I"),
                makeRoute(id: "R-tight", shortName: "T"),
                makeRoute(id: "R-comfortable", shortName: "C")
            ],
            trips: [
                timedTrip(id: "T-in", routeId: "R-in", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-tight", routeId: "R-tight", stops: [
                    ("S2", t(8, 17), t(8, 17)),
                    ("S3", t(8, 27), t(8, 27))
                ]),
                timedTrip(id: "T-comfortable", routeId: "R-comfortable", stops: [
                    ("S2", t(8, 18), t(8, 18)),
                    ("S3", t(8, 28), t(8, 28))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Origin", latitude: 49.600, longitude: 6.100),
            to: LocationPoint(id: "S3", name: "Destination", latitude: 49.620, longitude: 6.120)
        )

        let tight = try #require(calculation.options.first { $0.transitLegs.map(\.routeId) == ["R-in", "R-tight"] })
        #expect(tight.transitLegs.last?.transferWarning == "Tight connection — 2 min to change")

        #expect(calculation.options.allSatisfy {
            $0.transitLegs.map(\.routeId) != ["R-in", "R-comfortable"]
        })
    }

    @Test func delayedIncomingRideUsesNextScheduledConnectionWhenThatLineHasNoLiveData() async throws {
        // This mirrors the 223 → T1 failure mode: the originally selected tram is
        // missed after a live bus delay, but the next tram has timetable data only.
        // The repaired route must retain both legs instead of discarding the T1.
        let now = luxembourgDate(hour: 18, minute: 30)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-223", shortName: "223"),
                makeRoute(id: "R-T1", shortName: "T1", mode: "tram")
            ],
            trips: [
                timedTrip(id: "T-223", routeId: "R-223", stops: [
                    ("S1", t(18, 35), t(18, 35)),
                    ("S2", t(18, 50), t(18, 50))
                ]),
                timedTrip(id: "T-T1-early", routeId: "R-T1", stops: [
                    ("S2", t(18, 55), t(18, 55)),
                    ("S3", t(19, 10), t(19, 10))
                ]),
                timedTrip(id: "T-T1-next", routeId: "R-T1", stops: [
                    ("S2", t(19, 5), t(19, 5)),
                    ("S3", t(19, 25), t(19, 25))
                ])
            ]
        )
        let delayed223 = Departure(
            id: "live-223",
            stopId: "S1",
            routeId: "R-223",
            lineName: "223",
            destination: "Central",
            scheduledDeparture: luxembourgDate(hour: 18, minute: 35),
            realtimeDeparture: luxembourgDate(hour: 18, minute: 45),
            delayMinutes: 10,
            dataSource: .atpOpenAPI
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(departuresByStopId: ["S1": [delayed223]]),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12),
            time: .leaveNow,
            filters: RoutePlannerFilters(),
            realtimeRefreshPolicy: .forceRefresh
        )

        let repaired = try #require(calculation.options.first { option in
            option.transitLegs.map(\.tripId) == ["T-223", "T-T1-next"]
        })
        #expect(repaired.arrivalTime == luxembourgDate(hour: 19, minute: 25))
        #expect(repaired.transitLegs.first?.liveStatus == .delayed)
        #expect(repaired.transitLegs.last?.liveStatus == .scheduled)
        #expect(repaired.realtimeCoverage == .partial)
        #expect(repaired.status(at: now) == .partiallyLive)
        #expect(calculation.options.contains { option in
            option.transitLegs.map(\.tripId) == ["T-223", "T-T1-early"]
        } == false)
    }

    @Test func modePreferenceKeepsTramOptionDespiteCheaperBus() async throws {
        // B: the bus arrives sooner (cheaper comfort cost) but a tram exists; a tram
        // preference must keep the tram itinerary through truncation, not relax to bus.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(
            routes: [
                makeRoute(id: "R-bus", shortName: "B", mode: "bus"),
                makeRoute(id: "R-tram", shortName: "T", mode: "tram")
            ],
            trips: [
                timedTrip(id: "T-bus", routeId: "R-bus", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-tram", routeId: "R-tram", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 25), t(8, 25))
                ])
            ]
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .leaveNow,
            filters: RoutePlannerFilters(modePreference: .tram)
        )

        #expect(calculation.options.allSatisfy { option in
            option.transitLegs.contains { $0.mode == .tram }
        })
        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-tram")
    }

    @Test func synthesisesFootTransferBetweenNearbyStopsWithoutTransfersTable() async throws {
        // C1: changing lines at adjacent stops (S2 → S2b, ~11 m apart) with no transfers.txt
        // entry — the engine must synthesise the foot-transfer and find the 2-leg journey.
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1",
                    name: "Origin",
                    latitude: 49.60,
                    longitude: 6.10,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S2",
                    name: "Mid A",
                    latitude: 49.61,
                    longitude: 6.11,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S2b",
                    name: "Mid B",
                    latitude: 49.6101,
                    longitude: 6.11,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S3",
                    name: "Dest",
                    latitude: 49.62,
                    longitude: 6.12,
                    parentStation: nil,
                    platformCode: nil
                )
            ],
            routes: [makeRoute(id: "R-1", shortName: "1"), makeRoute(id: "R-2", shortName: "2")],
            services: [GTFSTimetableServiceEntry(
                id: "WEEK",
                weekdays: [],
                startDate: nil,
                endDate: nil,
                addedDates: ["20260614"],
                removedDates: []
            )],
            trips: [
                timedTrip(id: "T-1", routeId: "R-1", stops: [("S1", t(8, 5), t(8, 5)), ("S2", t(8, 15), t(8, 15))]),
                timedTrip(id: "T-2", routeId: "R-2", stops: [("S2b", t(8, 25), t(8, 25)), ("S3", t(8, 35), t(8, 35))])
            ],
            transfers: [],
            shapes: []
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S3", name: "Dest", latitude: 49.62, longitude: 6.12)
        )

        let option = try #require(calculation.options.first)
        #expect(option.transferCount == 1)
        #expect(option.transitLegs.map(\.routeId) == ["R-1", "R-2"])
    }

    @Test func findsPreviousServiceDayTripAfterMidnight() async throws {
        // C2: at 00:20 the only ride to S2 is yesterday's 24:20 trip (previous service day,
        // crossing midnight). The engine must shift it onto today's clock and find it.
        let now = luxembourgDate(hour: 0, minute: 20)
        let nightTrip = GTFSTimetableTripEntry(
            id: "T-night", routeId: "R-night", serviceId: "NIGHT", headsign: "Central",
            directionId: nil, shapeId: nil,
            stopTimes: [
                GTFSTimetableStopTimeEntry(
                    stopId: "S1",
                    arrivalSeconds: t(24, 30),
                    departureSeconds: t(24, 30),
                    sequence: 1,
                    headsign: nil,
                    pickupType: nil,
                    dropOffType: nil,
                    shapeDistanceTraveled: nil
                ),
                GTFSTimetableStopTimeEntry(
                    stopId: "S2",
                    arrivalSeconds: t(24, 50),
                    departureSeconds: t(24, 50),
                    sequence: 2,
                    headsign: nil,
                    pickupType: nil,
                    dropOffType: nil,
                    shapeDistanceTraveled: nil
                )
            ]
        )
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1",
                    name: "Hill Lift",
                    latitude: 49.6,
                    longitude: 6.1,
                    parentStation: nil,
                    platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S2",
                    name: "Central",
                    latitude: 49.61,
                    longitude: 6.11,
                    parentStation: nil,
                    platformCode: nil
                )
            ],
            routes: [makeRoute(id: "R-night", shortName: "N")],
            services: [GTFSTimetableServiceEntry(
                id: "NIGHT",
                weekdays: [],
                startDate: nil,
                endDate: nil,
                addedDates: ["20260613"],
                removedDates: []
            )],
            trips: [nightTrip],
            transfers: [],
            shapes: []
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let transitLeg = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(transitLeg.routeId == "R-night")

        let arriveBy = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(luxembourgDate(hour: 0, minute: 55))
        )
        #expect(arriveBy.options.first?.transitLegs.first?.routeId == "R-night")
    }

    @Test func leaveNowOptionIDsAreStableAcrossRecalculation() async throws {
        // D1: the same itinerary recalculated a minute later keeps its option ID, so the
        // rider's selection survives a refresh (old IDs embedded the wall clock).
        var currentNow = luxembourgDate(hour: 8, minute: 0)
        let timetable = makeTimetable(trips: [makeTrip(id: "T15", routeId: "R15", departure: t(8, 5))])
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { currentNow }
        )
        let from = LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001)
        let to = LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)

        let first = try await routeService.calculateRoute(from: from, to: to)
        currentNow = luxembourgDate(hour: 8, minute: 1)
        let second = try await routeService.calculateRoute(from: from, to: to)

        #expect(first.options.first?.id == second.options.first?.id)
    }

    @Test func collapsesOverlappingTransferStopsIntoOneOption() async throws {
        // Lines A and B share stops S2 and S3, so a rider can change at either while
        // riding the exact same two vehicles. Before, the engine surfaced one option per
        // overlapping transfer stop; now they collapse to a single journey that stays
        // aboard the first bus to the last shared stop (S3).
        let now = luxembourgDate(hour: 8, minute: 0)
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "S1", name: "Origin", latitude: 49.600, longitude: 6.100,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S2", name: "Mid A", latitude: 49.610, longitude: 6.110,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S3", name: "Mid B", latitude: 49.620, longitude: 6.120,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "S4", name: "Dest", latitude: 49.630, longitude: 6.130,
                    parentStation: nil, platformCode: nil
                )
            ],
            routes: [makeRoute(id: "R-A", shortName: "A"), makeRoute(id: "R-B", shortName: "B")],
            services: [GTFSTimetableServiceEntry(
                id: "WEEK", weekdays: [], startDate: nil, endDate: nil,
                addedDates: ["20260614"], removedDates: []
            )],
            trips: [
                timedTrip(id: "T-A", routeId: "R-A", stops: [
                    ("S1", t(8, 5), t(8, 5)),
                    ("S2", t(8, 10), t(8, 10)),
                    ("S3", t(8, 15), t(8, 15))
                ]),
                timedTrip(id: "T-B", routeId: "R-B", stops: [
                    ("S2", t(8, 14), t(8, 14)),
                    ("S3", t(8, 20), t(8, 20)),
                    ("S4", t(8, 30), t(8, 30))
                ])
            ],
            transfers: [],
            shapes: []
        )
        let routeService = PublicTransportRouteService(
            gtfsService: MockGTFSService(timetable: timetable),
            atpClient: MockATPClient(),
            roadRouteProvider: MockRoadRouteProvider(),
            now: { now }
        )

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(name: "Current Location", latitude: 49.6001, longitude: 6.1001),
            to: LocationPoint(id: "S4", name: "Dest", latitude: 49.630, longitude: 6.130)
        )

        #expect(calculation.options.count == 1)
        let option = try #require(calculation.options.first)
        #expect(option.transitLegs.map(\.routeId) == ["R-A", "R-B"])
        // Equal-time transfer points are deterministically collapsed to one signature.
        #expect(option.transitLegs.first?.destinationStopId == "S2")
        #expect(option.transitLegs.last?.originStopId == "S2")
    }

    private func luxembourgDate(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 14,
            hour: hour,
            minute: minute
        ))!
    }
}

private struct MockGTFSService: GTFSService {
    let timetable: GTFSTimetableIndexPayload?

    nonisolated func searchStops(query _: String) async -> [Stop] {
        []
    }

    nonisolated func stopsForMap(
        center _: LocationPoint,
        latitudeDelta _: Double,
        longitudeDelta _: Double,
        limit _: Int
    ) async -> [Stop] {
        []
    }

    nonisolated func stop(id: String) async -> Stop? {
        timetable?.stops.first { $0.id == id }.map { stop in
            Stop(
                id: stop.id,
                name: stop.name,
                location: stop.location,
                modes: [.bus],
                dataSource: .gtfs
            )
        }
    }

    nonisolated func allStops() async -> [Stop] {
        []
    }

    nonisolated func routesForStop(id _: String) async -> [TransitRoute] {
        []
    }

    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload? {
        timetable
    }
}

private struct MockATPClient: ATPClient {
    var departuresByStopId: [String: [Departure]] = [:]

    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId: String) async throws -> [Departure] {
        departuresByStopId[stopId, default: []]
    }

    func departureBoards(stopIds: [String]) async throws -> [Departure] {
        ATPMapper.mergedDepartures(stopIds.flatMap { departuresByStopId[$0, default: []] })
    }
}

private nonisolated final class CountingATPClient: ATPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var boardCallCount: Int {
        lock.withLock { calls }
    }

    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId _: String) async throws -> [Departure] {
        lock.withLock { calls += 1 }
        return []
    }
}

private nonisolated final class ConcurrencyTrackingATPClient: ATPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maximum = 0

    var maximumInFlight: Int {
        lock.withLock { maximum }
    }

    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId _: String) async throws -> [Departure] {
        []
    }

    func departureBoards(stopIds _: [String]) async throws -> [Departure] {
        lock.withLock {
            inFlight += 1
            maximum = max(maximum, inFlight)
        }
        defer {
            lock.withLock { inFlight -= 1 }
        }

        try await Task.sleep(for: .milliseconds(25))
        return []
    }
}

private struct MockBikeShareService: BikeShareService {
    let stations: [BikeShareStation]
    let fetchedAt: Date

    func bikeShareStations(near _: LocationPoint) async -> [BikeShareStation] {
        stations
    }

    func refreshStaticStations() async {}
    func refreshAvailability() async {}

    func snapshot() async -> BikeShareSnapshot? {
        BikeShareSnapshot(stations: stations, fetchedAt: fetchedAt)
    }
}

private struct MockRoadRouteProvider: RoadRouteProviding {
    var routes: [String: [RouteMapCoordinate]] = [:]

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        routes["\(origin.latitude),\(origin.longitude)|\(destination.latitude),\(destination.longitude)"]
    }
}

private enum RouteTestTimeout: Error {
    case expired
}

private func completeWithin<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .milliseconds(max(1, Int((seconds * 1_000).rounded()))))
            throw RouteTestTimeout.expired
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

private final class SlowRoadRouteProvider: RoadRouteProviding, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        lock.withLock { calls += 1 }
        try? await Task.sleep(for: .seconds(10))
        return [RouteMapCoordinate(origin), RouteMapCoordinate(destination)]
    }
}

private struct SlowBikeShareService: BikeShareService {
    func bikeShareStations(near _: LocationPoint) async -> [BikeShareStation] {
        []
    }

    func refreshStaticStations() async {}

    func refreshAvailability() async {
        try? await Task.sleep(for: .seconds(10))
    }

    func snapshot() async -> BikeShareSnapshot? { nil }
}

private struct SlowATPClient: ATPClient {
    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId _: String) async throws -> [Departure] {
        try await Task.sleep(for: .seconds(10))
        return []
    }

    func departureBoards(stopIds _: [String]) async throws -> [Departure] {
        try await Task.sleep(for: .seconds(10))
        return []
    }
}

private nonisolated final class ConcurrencyTrackingRoadRouteProvider: RoadRouteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maximum = 0
    private var nextDelayIndex = 0
    private var calls = 0

    var maximumInFlight: Int {
        lock.withLock { maximum }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        let delayMilliseconds = lock.withLock {
            let delays = [45, 5, 25]
            let delay = delays[nextDelayIndex % delays.count]
            nextDelayIndex += 1
            calls += 1
            return delay
        }
        lock.withLock {
            inFlight += 1
            maximum = max(maximum, inFlight)
        }
        defer {
            lock.withLock { inFlight -= 1 }
        }

        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        return [RouteMapCoordinate(origin), RouteMapCoordinate(destination)]
    }
}

private nonisolated final class CancellationAwareRoadRouteProvider: RoadRouteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    var hasStarted: Bool {
        lock.withLock { started }
    }

    nonisolated func roadRouteCoordinates(
        from origin: LocationPoint,
        to destination: LocationPoint,
        transport _: RoadRouteTransport
    ) async -> [RouteMapCoordinate]? {
        lock.withLock { started = true }
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        return [RouteMapCoordinate(origin), RouteMapCoordinate(destination)]
    }
}
