import Foundation
import Testing

@testable import Verkeier

struct LineDetailServiceTests {
    @Test func detailBuildsDirectionsStopsTimetableAndShapeOverlay() {
        let service = LineDetailService(calendar: luxCalendar)
        let timetable = makeTimetable()
        let route = TransitRoute(
            id: "route-t1",
            shortName: "T1",
            longName: "Luxembourg Gare - Luxexpo",
            mode: .tram,
            dataSource: .gtfs
        )

        let detail = service.detail(
            for: route,
            selectedStopId: "stop-b",
            timetable: timetable,
            now: testDate(hour: 8, minute: 2)
        )

        #expect(detail?.route.id == "route-t1")
        #expect(detail?.directions.count == 2)
        #expect(detail?.selectedDirectionID == "0|Luxexpo")
        #expect(detail?.stopSequence.map(\.id) == ["stop-a", "stop-b", "stop-c"])
        #expect(detail?.stopSequence.map(\.platform) == ["1", "2", "3"])
        #expect(detail?.upcomingDepartures.map(\.id) == ["trip-1-stop-b", "trip-2-stop-b"])
        #expect(detail?.mapOverlay?.segments.first?.coordinates.count == 3)
    }

    @Test func detailOmitsBlankPlatformCodes() {
        let service = LineDetailService(calendar: luxCalendar)
        var timetable = makeTimetable()
        timetable = GTFSTimetableIndexPayload(
            source: timetable.source,
            stops: timetable.stops.map { stop in
                GTFSTimetableStopEntry(
                    id: stop.id,
                    name: stop.name,
                    latitude: stop.latitude,
                    longitude: stop.longitude,
                    parentStation: stop.parentStation,
                    platformCode: stop.id == "stop-b" ? "  \n" : stop.platformCode
                )
            },
            routes: timetable.routes,
            services: timetable.services,
            trips: timetable.trips,
            transfers: timetable.transfers,
            shapes: timetable.shapes
        )
        let route = TransitRoute(
            id: "route-t1",
            shortName: "T1",
            longName: "Luxembourg Gare - Luxexpo",
            mode: .tram,
            dataSource: .gtfs
        )

        let detail = service.detail(
            for: route,
            selectedStopId: "stop-b",
            timetable: timetable,
            now: testDate(hour: 8, minute: 2)
        )

        #expect(detail?.stopSequence.first(where: { $0.id == "stop-b" })?.platform == nil)
    }

    @Test func detailRespectsSelectedDirectionOverride() {
        let service = LineDetailService(calendar: luxCalendar)
        let timetable = makeTimetable()
        let route = TransitRoute(
            id: "route-t1",
            shortName: "T1",
            longName: "Luxembourg Gare - Luxexpo",
            mode: .tram,
            dataSource: .gtfs
        )

        let detail = service.detail(
            for: route,
            selectedStopId: "stop-b",
            timetable: timetable,
            now: testDate(hour: 8, minute: 2),
            selectedDirectionID: "1|Gare Centrale"
        )

        #expect(detail?.selectedDirectionID == "1|Gare Centrale")
        #expect(detail?.stopSequence.map(\.id) == ["stop-c", "stop-b", "stop-a"])
    }

    private func makeTimetable() -> GTFSTimetableIndexPayload {
        GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(id: "stop-a", name: "Gare Centrale", latitude: 49.60, longitude: 6.13, parentStation: nil, platformCode: "1"),
                GTFSTimetableStopEntry(id: "stop-b", name: "Hamilius", latitude: 49.61, longitude: 6.12, parentStation: nil, platformCode: "2"),
                GTFSTimetableStopEntry(id: "stop-c", name: "Luxexpo", latitude: 49.63, longitude: 6.16, parentStation: nil, platformCode: "3")
            ],
            routes: [
                GTFSTimetableRouteEntry(
                    id: "route-t1",
                    shortName: "T1",
                    longName: "Luxembourg Gare - Luxexpo",
                    mode: "tram",
                    operatorName: "AVL"
                )
            ],
            services: [
                GTFSTimetableServiceEntry(
                    id: "weekday",
                    weekdays: Set([1, 2, 3, 4, 5, 6, 7]),
                    startDate: "20260101",
                    endDate: "20261231",
                    addedDates: [],
                    removedDates: []
                )
            ],
            trips: [
                GTFSTimetableTripEntry(
                    id: "trip-1",
                    routeId: "route-t1",
                    serviceId: "weekday",
                    headsign: "Luxexpo",
                    directionId: "0",
                    shapeId: "shape-outbound",
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(stopId: "stop-a", arrivalSeconds: 28_800, departureSeconds: 28_800, sequence: 1, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 0),
                        GTFSTimetableStopTimeEntry(stopId: "stop-b", arrivalSeconds: 29_100, departureSeconds: 29_100, sequence: 2, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 1000),
                        GTFSTimetableStopTimeEntry(stopId: "stop-c", arrivalSeconds: 29_400, departureSeconds: 29_400, sequence: 3, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 2000)
                    ]
                ),
                GTFSTimetableTripEntry(
                    id: "trip-2",
                    routeId: "route-t1",
                    serviceId: "weekday",
                    headsign: "Luxexpo",
                    directionId: "0",
                    shapeId: "shape-outbound",
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(stopId: "stop-a", arrivalSeconds: 30_000, departureSeconds: 30_000, sequence: 1, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 0),
                        GTFSTimetableStopTimeEntry(stopId: "stop-b", arrivalSeconds: 30_300, departureSeconds: 30_300, sequence: 2, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 1000),
                        GTFSTimetableStopTimeEntry(stopId: "stop-c", arrivalSeconds: 30_600, departureSeconds: 30_600, sequence: 3, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: 2000)
                    ]
                ),
                GTFSTimetableTripEntry(
                    id: "trip-return",
                    routeId: "route-t1",
                    serviceId: "weekday",
                    headsign: "Gare Centrale",
                    directionId: "1",
                    shapeId: nil,
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(stopId: "stop-c", arrivalSeconds: 29_700, departureSeconds: 29_700, sequence: 1, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: nil),
                        GTFSTimetableStopTimeEntry(stopId: "stop-b", arrivalSeconds: 30_000, departureSeconds: 30_000, sequence: 2, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: nil),
                        GTFSTimetableStopTimeEntry(stopId: "stop-a", arrivalSeconds: 30_300, departureSeconds: 30_300, sequence: 3, headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: nil)
                    ]
                )
            ],
            transfers: [],
            shapes: [
                GTFSTimetableShapeEntry(
                    id: "shape-outbound",
                    points: [
                        GTFSTimetableShapePoint(latitude: 49.60, longitude: 6.13, sequence: 1, distanceTraveled: 0),
                        GTFSTimetableShapePoint(latitude: 49.61, longitude: 6.12, sequence: 2, distanceTraveled: 1000),
                        GTFSTimetableShapePoint(latitude: 49.63, longitude: 6.16, sequence: 3, distanceTraveled: 2000)
                    ]
                )
            ]
        )
    }

    private func testDate(hour: Int, minute: Int) -> Date {
        luxCalendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: hour, minute: minute))!
    }

    private var luxCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg")!
        return calendar
    }
}
