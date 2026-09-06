import Foundation
import Testing
@testable import Verkeier

struct OfflineScheduleServiceTests {
    @Test func upcomingDeparturesExcludesTripAtItsFinalStop() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "terminal",
            name: "Charlys Statioun",
            location: LocationPoint(name: "Charlys Statioun", latitude: 49.65, longitude: 6.22),
            modes: [.bus],
            dataSource: .gtfs
        )
        let timetable = GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "origin", name: "Origin", latitude: 49.6, longitude: 6.1,
                    parentStation: nil, platformCode: nil
                ),
                GTFSTimetableStopEntry(
                    id: "terminal", name: "Charlys Statioun", latitude: 49.65, longitude: 6.22,
                    parentStation: nil, platformCode: nil
                )
            ],
            routes: [GTFSTimetableRouteEntry(
                id: "route-29", shortName: "29", longName: nil, mode: "bus", operatorName: nil
            )],
            services: [GTFSTimetableServiceEntry(
                id: "daily", weekdays: Set(1 ... 7), startDate: nil, endDate: nil,
                addedDates: [], removedDates: []
            )],
            trips: [GTFSTimetableTripEntry(
                id: "incoming-29",
                routeId: "route-29",
                serviceId: "daily",
                headsign: "Charlys Statioun",
                directionId: nil,
                shapeId: nil,
                stopTimes: [
                    GTFSTimetableStopTimeEntry(
                        stopId: "origin", arrivalSeconds: 28_800, departureSeconds: 28_800, sequence: 1,
                        headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: nil
                    ),
                    GTFSTimetableStopTimeEntry(
                        stopId: "terminal", arrivalSeconds: 29_400, departureSeconds: 29_400, sequence: 2,
                        headsign: nil, pickupType: nil, dropOffType: nil, shapeDistanceTraveled: nil
                    )
                ]
            )],
            transfers: [],
            shapes: []
        )

        let departures = service.upcomingDepartures(
            for: stop,
            timetable: timetable,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5)
        )

        #expect(departures.isEmpty)
    }

    @Test func departureBoardMergerPrefersLiveAndMarksScheduledStatusUnknown() {
        let firstDeparture = Date(timeIntervalSince1970: 1_800)
        let live = Departure(
            id: "live-t1",
            stopId: "stop-1",
            lineName: "T1",
            destination: "Luxexpo",
            scheduledDeparture: firstDeparture,
            realtimeDeparture: firstDeparture.addingTimeInterval(60),
            delayMinutes: 1,
            platform: "2",
            dataSource: .atpOpenAPI
        )
        let scheduled = [
            OfflineScheduleDeparture(
                id: "duplicate-t1",
                lineName: "T1",
                destination: "",
                departureDate: firstDeparture,
                platform: nil,
                mode: .tram
            ),
            OfflineScheduleDeparture(
                id: "scheduled-t1",
                lineName: "T1",
                destination: "Luxexpo",
                departureDate: firstDeparture.addingTimeInterval(120),
                platform: "2",
                mode: .tram
            )
        ]

        let merged = DepartureBoardMerger.merge(
            live: [live], scheduled: scheduled, stopID: "stop-1"
        )

        #expect(merged.map(\.id) == ["live-t1", "gtfs-scheduled-t1"])
        #expect(merged.last?.status == .unknown)
        #expect(merged.last?.stopId == "stop-1")
    }

    @Test func departureBoardMergerSharesPlatformHintsAcrossLiveAndScheduledRows() {
        let firstDeparture = Date(timeIntervalSince1970: 1_800)
        let live = [
            Departure(
                id: "live-outbound",
                stopId: "platform-2",
                lineName: "2",
                destination: "Bonnevoie",
                scheduledDeparture: firstDeparture,
                platform: "2",
                dataSource: .atpOpenAPI
            ),
            Departure(
                id: "live-inbound",
                stopId: "platform-1",
                lineName: "2",
                destination: "Limpertsberg",
                scheduledDeparture: firstDeparture.addingTimeInterval(60),
                platform: "1",
                dataSource: .atpOpenAPI
            ),
        ]
        let scheduled = [
            OfflineScheduleDeparture(
                id: "scheduled-outbound",
                lineName: "2",
                destination: "Bonnevoie",
                departureDate: firstDeparture.addingTimeInterval(120),
                platform: nil,
                mode: .bus
            ),
            OfflineScheduleDeparture(
                id: "scheduled-inbound",
                lineName: "2",
                destination: "Limpertsberg",
                departureDate: firstDeparture.addingTimeInterval(180),
                platform: nil,
                mode: .bus
            ),
        ]

        let merged = DepartureBoardMerger.merge(live: live, scheduled: scheduled, stopID: "stop-1")

        #expect(merged.map(\.platform) == ["2", "1", "2", "1"])
    }

    @Test func departureBoardMergerDoesNotGuessAcrossConflictingDestinations() {
        let firstDeparture = Date(timeIntervalSince1970: 1_800)
        let live = [
            Departure(
                id: "live-one",
                stopId: "platform-1",
                lineName: "2",
                destination: "North",
                scheduledDeparture: firstDeparture,
                platform: "1",
                dataSource: .atpOpenAPI
            ),
            Departure(
                id: "live-two",
                stopId: "platform-2",
                lineName: "2",
                destination: "South",
                scheduledDeparture: firstDeparture.addingTimeInterval(60),
                platform: "2",
                dataSource: .atpOpenAPI
            ),
        ]
        let scheduled = [
            OfflineScheduleDeparture(
                id: "scheduled-unknown",
                lineName: "2",
                destination: "",
                departureDate: firstDeparture.addingTimeInterval(120),
                platform: nil,
                mode: .bus
            )
        ]

        let merged = DepartureBoardMerger.merge(live: live, scheduled: scheduled, stopID: "stop-1")

        #expect(merged.last?.platform == nil)
    }

    @Test func upcomingDeparturesUsesActiveServiceAndSortsByTime() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "stop-1",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(name: "Hamilius", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .gtfs
        )

        let departures = service.upcomingDepartures(
            for: stop,
            timetable: timetable,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 8
        )

        #expect(departures.map(\.lineName) == ["4", "10"])
        #expect(departures.map(\.destination) == ["Gare", "Kirchberg"])
    }

    @Test func upcomingDeparturesFallsBackToMatchingStopName() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let groupedStop = Stop(
            id: "grouped-stop",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(name: "Hamilius", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .atpOpenAPI,
            platformIds: ["missing-platform"]
        )

        let departures = service.upcomingDepartures(
            for: groupedStop,
            timetable: timetable,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 4
        )

        #expect(departures.count == 2)
        #expect(departures.first?.lineName == "4")
    }

    @Test func upcomingDeparturesMatchesLeadingZeroIDsAndUsesPlatformCode() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "200405060",
            name: "Platformed Stop",
            location: LocationPoint(name: "Platformed Stop", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .atpOpenAPI,
            platformIds: ["200405060"]
        )

        let departures = service.upcomingDepartures(
            for: stop,
            timetable: leadingZeroPlatformTimetable,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 4
        )

        #expect(departures.count == 1)
        #expect(departures.first?.platform == "4")
    }

    @Test func upcomingDeparturesUsesOnlyExplicitNumberedStopNamePlatformSuffix() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "named-stop",
            name: "Cloche d'Or",
            location: LocationPoint(name: "Cloche d'Or", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .gtfs
        )

        let numbered = service.upcomingDepartures(
            for: stop,
            timetable: namedPlatformTimetable(stopName: "Gasperich, prov. Cloche d'Or Quai 4"),
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 4
        )
        let unnumbered = service.upcomingDepartures(
            for: stop,
            timetable: namedPlatformTimetable(stopName: "Gasperich, prov. Cloche d'Or Quais"),
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 4
        )

        #expect(numbered.first?.platform == "4")
        #expect(unnumbered.first?.platform == nil)
    }

    @Test func stopNotInIndexReturnsEmpty() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let unknown = Stop(
            id: "nope",
            name: "Nowhere",
            location: LocationPoint(name: "Nowhere", latitude: 0, longitude: 0),
            modes: [.bus],
            dataSource: .gtfs
        )
        let departures = service.upcomingDepartures(
            for: unknown,
            timetable: timetable,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 8
        )
        #expect(departures.isEmpty)
    }

    @Test func noActiveServiceForDayReturnsEmpty() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "stop-1",
            name: "Hamilius",
            location: LocationPoint(name: "Hamilius", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .gtfs
        )
        // 2026-06-21 is a Sunday; the only service runs Mondays (weekday 2).
        let departures = service.upcomingDepartures(
            for: stop,
            timetable: timetable,
            now: makeDate(year: 2026, month: 6, day: 21, hour: 8, minute: 5),
            limit: 8
        )
        #expect(departures.isEmpty)
    }

    @Test func emptyTimetableReturnsEmpty() {
        let service = OfflineScheduleService(calendar: luxCalendar)
        let stop = Stop(
            id: "stop-1",
            name: "Hamilius",
            location: LocationPoint(name: "Hamilius", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .gtfs
        )
        let empty = GTFSTimetableIndexPayload(
            source: "empty", stops: [], routes: [], services: [], trips: [], transfers: [], shapes: []
        )
        let departures = service.upcomingDepartures(
            for: stop,
            timetable: empty,
            now: makeDate(year: 2026, month: 6, day: 22, hour: 8, minute: 5),
            limit: 8
        )
        #expect(departures.isEmpty)
    }

    private var luxCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Luxembourg") ?? .current
        return calendar
    }

    private var timetable: GTFSTimetableIndexPayload {
        GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "stop-1",
                    name: "Hamilius",
                    latitude: 49.6116,
                    longitude: 6.1319,
                    parentStation: nil,
                    platformCode: "1"
                )
            ],
            routes: [
                GTFSTimetableRouteEntry(
                    id: "route-4",
                    shortName: "4",
                    longName: "Centre",
                    mode: "bus",
                    operatorName: nil
                ),
                GTFSTimetableRouteEntry(
                    id: "route-10",
                    shortName: "10",
                    longName: "Kirchberg",
                    mode: "bus",
                    operatorName: nil
                )
            ],
            services: [
                GTFSTimetableServiceEntry(
                    // Foundation weekday order (Sun=1 ... Sat=7), as GTFSIndexBuilder
                    // produces. 2026-06-22 is a Monday → 2.
                    id: "weekday",
                    weekdays: [2],
                    startDate: "20260601",
                    endDate: "20260630",
                    addedDates: [],
                    removedDates: []
                )
            ],
            trips: [
                GTFSTimetableTripEntry(
                    id: "trip-4",
                    routeId: "route-4",
                    serviceId: "weekday",
                    headsign: "Gare",
                    directionId: nil,
                    shapeId: nil,
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(
                            stopId: "stop-1",
                            arrivalSeconds: 8 * 3600 + 10 * 60,
                            departureSeconds: 8 * 3600 + 10 * 60,
                            sequence: 1,
                            headsign: "Gare",
                            pickupType: nil,
                            dropOffType: nil,
                            shapeDistanceTraveled: nil
                        )
                    ]
                ),
                GTFSTimetableTripEntry(
                    id: "trip-10",
                    routeId: "route-10",
                    serviceId: "weekday",
                    headsign: "Kirchberg",
                    directionId: nil,
                    shapeId: nil,
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(
                            stopId: "stop-1",
                            arrivalSeconds: 8 * 3600 + 24 * 60,
                            departureSeconds: 8 * 3600 + 24 * 60,
                            sequence: 1,
                            headsign: "Kirchberg",
                            pickupType: nil,
                            dropOffType: nil,
                            shapeDistanceTraveled: nil
                        )
                    ]
                )
            ],
            transfers: [],
            shapes: []
        )
    }

    private var leadingZeroPlatformTimetable: GTFSTimetableIndexPayload {
        GTFSTimetableIndexPayload(
            source: "test",
            stops: [
                GTFSTimetableStopEntry(
                    id: "000200405060",
                    name: "Platformed Stop",
                    latitude: 49.6116,
                    longitude: 6.1319,
                    parentStation: nil,
                    platformCode: "4"
                )
            ],
            routes: [
                GTFSTimetableRouteEntry(
                    id: "route-platform",
                    shortName: "P",
                    longName: "Platformed",
                    mode: "bus",
                    operatorName: nil
                )
            ],
            services: [
                GTFSTimetableServiceEntry(
                    id: "weekday",
                    weekdays: [2],
                    startDate: "20260601",
                    endDate: "20260630",
                    addedDates: [],
                    removedDates: []
                )
            ],
            trips: [
                GTFSTimetableTripEntry(
                    id: "trip-platform",
                    routeId: "route-platform",
                    serviceId: "weekday",
                    headsign: "Centre",
                    directionId: nil,
                    shapeId: nil,
                    stopTimes: [
                        GTFSTimetableStopTimeEntry(
                            stopId: "000200405060",
                            arrivalSeconds: 8 * 3600 + 10 * 60,
                            departureSeconds: 8 * 3600 + 10 * 60,
                            sequence: 1,
                            headsign: "Centre",
                            pickupType: nil,
                            dropOffType: nil,
                            shapeDistanceTraveled: nil
                        )
                    ]
                )
            ],
            transfers: [],
            shapes: []
        )
    }

    private func namedPlatformTimetable(stopName: String) -> GTFSTimetableIndexPayload {
        var timetable = leadingZeroPlatformTimetable
        let stop = GTFSTimetableStopEntry(
            id: "named-stop",
            name: stopName,
            latitude: 49.6116,
            longitude: 6.1319,
            parentStation: nil,
            platformCode: nil
        )
        let trip = GTFSTimetableTripEntry(
            id: "trip-named-platform",
            routeId: "route-platform",
            serviceId: "weekday",
            headsign: "Centre",
            directionId: nil,
            shapeId: nil,
            stopTimes: [
                GTFSTimetableStopTimeEntry(
                    stopId: "named-stop",
                    arrivalSeconds: 8 * 3600 + 10 * 60,
                    departureSeconds: 8 * 3600 + 10 * 60,
                    sequence: 1,
                    headsign: "Centre",
                    pickupType: nil,
                    dropOffType: nil,
                    shapeDistanceTraveled: nil
                )
            ]
        )
        timetable = GTFSTimetableIndexPayload(
            source: timetable.source,
            stops: [stop],
            routes: timetable.routes,
            services: timetable.services,
            trips: [trip],
            transfers: [],
            shapes: []
        )
        return timetable
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        luxCalendar.date(from: DateComponents(
            timeZone: luxCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
