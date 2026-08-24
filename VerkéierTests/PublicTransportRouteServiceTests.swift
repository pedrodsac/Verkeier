import Foundation
import Testing
@testable import Verkeier

struct PublicTransportRouteServiceTests {
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
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
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
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
        )

        let walk = try #require(calculation.plan.legs.first { $0.transportKind == .walking })
        let transit = try #require(calculation.plan.legs.first { $0.transportKind == .transit })
        #expect(walk.arrivalTime == liveDeparture)
        #expect(walk.scheduledArrivalTime == liveDeparture)
        #expect(walk.departureTime == walk.scheduledDepartureTime)
        #expect(walk.arrivalTime == transit.realtimeDepartureTime)
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
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
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

    @Test func rejectsWalkingOnlyRoutes() async throws {
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
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
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

    @Test func directRouteOutranksFasterButMoreTransferredItinerary() async throws {
        // Direct trip arrives 8:25; a 1-transfer itinerary arrives 8:23 (2 min sooner).
        // Old arrival-only ranking put the transfer first; comfort cost now favours
        // the direct journey.
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
        #expect(first.transferCount == 0)
        #expect(first.plan.legs.first { $0.transportKind == .transit }?.routeId == "R15")
        // The faster transfer itinerary is still offered, just ranked lower.
        #expect(calculation.options.contains { $0.transferCount == 1 })
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
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11)
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
            to: LocationPoint(id: "S3", name: "Airport", latitude: 49.62, longitude: 6.12)
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

    private func makeTimetable(
        routes: [GTFSTimetableRouteEntry]? = nil,
        trips: [GTFSTimetableTripEntry]? = nil,
        transfers: [GTFSTimetableTransferEntry] = [],
        shapes: [GTFSTimetableShapeEntry] = []
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
            services: [
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

        let bikeOption = try #require(calculation.options.first { option in
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
            time: .arriveBy(deadline)
        )

        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-on-time")
        let delayed = try #require(calculation.options.first {
            $0.transitLegs.first?.routeId == "R-delayed"
        })
        #expect(delayed.arrivalTime == luxembourgDate(hour: 8, minute: 35))
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

        let calculation = try await routeService.calculateRoute(
            from: LocationPoint(id: "S1", name: "Hill Lift", latitude: 49.6, longitude: 6.1),
            to: LocationPoint(id: "S2", name: "Central", latitude: 49.61, longitude: 6.11),
            time: .arriveBy(deadline)
        )

        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-less-late")
        #expect(calculation.options.first?.arrivalTime == luxembourgDate(hour: 8, minute: 35))
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
            to: LocationPoint(id: "S3", name: "Destination", latitude: 49.620, longitude: 6.120)
        )

        #expect(calculation.options.first?.transitLegs.first?.routeId == "R-direct")
        let broken = try #require(calculation.options.first { option in
            option.transitLegs.map(\.routeId) == ["R-in", "R-next"]
        })
        #expect(broken.transitLegs.last?.transferWarning == "Connection may be missed")
        #expect(broken.transitLegs.first?.transferWarning == nil)
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
        // Stayed aboard line A to the last shared stop (S3) rather than changing at S2.
        #expect(option.transitLegs.first?.destinationStopId == "S3")
        #expect(option.transitLegs.last?.originStopId == "S3")
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
