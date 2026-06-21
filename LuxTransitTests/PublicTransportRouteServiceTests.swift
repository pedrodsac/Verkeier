import Foundation
import Testing

@testable import LuxTransit

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
            transfers: [],
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

    nonisolated func searchStops(query: String) async -> [Stop] {
        []
    }

    nonisolated func stopsForMap(
        center: LocationPoint,
        latitudeDelta: Double,
        longitudeDelta: Double,
        limit: Int
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

    nonisolated func routesForStop(id: String) async -> [TransitRoute] {
        []
    }

    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload? {
        timetable
    }
}

private struct MockATPClient: ATPClient {
    var departuresByStopId: [String: [Departure]] = [:]

    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId: String) async throws -> [Departure] {
        departuresByStopId[stopId, default: []]
    }

    func departureBoards(stopIds: [String]) async throws -> [Departure] {
        ATPMapper.mergedDepartures(stopIds.flatMap { departuresByStopId[$0, default: []] })
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
