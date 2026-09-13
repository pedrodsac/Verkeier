import Foundation
import Testing
@testable import Verkeier

struct StopDetailPresentationTests {
    @Test func appliesPlatformFilterAfterLiveAndScheduledRowsAreMerged() {
        let firstDeparture = Date(timeIntervalSince1970: 1_800)
        let stop = Stop(
            id: "stop-1",
            name: "Central",
            location: LocationPoint(name: "Central", latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: .mock
        )
        let lineOne = TransitRoute(id: "route-1", shortName: "1", mode: .bus, dataSource: .mock)
        let lineTwo = TransitRoute(id: "route-2", shortName: "2", mode: .bus, dataSource: .mock)
        let live = [
            Departure(
                id: "live-1",
                stopId: "stop-1",
                routeId: lineOne.id,
                lineName: "1",
                destination: "North",
                scheduledDeparture: firstDeparture,
                platform: "1",
                dataSource: .atpOpenAPI
            ),
            Departure(
                id: "live-2",
                stopId: "stop-1",
                routeId: lineTwo.id,
                lineName: "2",
                destination: "South",
                scheduledDeparture: firstDeparture.addingTimeInterval(60),
                platform: "2",
                dataSource: .atpOpenAPI
            )
        ]
        let scheduled = [
            OfflineScheduleDeparture(
                id: "scheduled-1",
                lineName: "1",
                destination: "North",
                departureDate: firstDeparture,
                platform: nil,
                mode: .bus
            ),
            OfflineScheduleDeparture(
                id: "scheduled-2",
                lineName: "2",
                destination: "South",
                departureDate: firstDeparture.addingTimeInterval(60),
                platform: nil,
                mode: .bus
            )
        ]
        let model = StopDetailPresentationModel(
            stop: stop,
            routes: [lineOne, lineTwo],
            departures: live,
            offlineScheduledDepartures: scheduled,
            alerts: [],
            availablePlatforms: ["1", "2"],
            selectedLine: nil,
            selectedPlatform: "2",
            isLoadingDepartures: false,
            errorMessage: nil,
            lastUpdated: nil,
            isStale: false,
            isFavourite: false,
            trackedDepartureId: nil,
            liveActivityErrorMessage: nil,
            liveActivityStaleMessage: "",
            activeReminder: nil,
            departureReminderErrorMessage: nil
        )

        #expect(model.mergedDepartures.map(\.id) == ["live-2"])
        #expect(model.mergedDepartures.first?.platform == "2")
        #expect(model.scheduledDepartures.isEmpty)
    }

    @Test func keepsScheduledRowsSeparateAndLabelsThemAsGTFS() {
        let stop = Stop(
            id: "stop-1",
            name: "Central",
            location: LocationPoint(name: "Central", latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: .gtfs,
            gtfsStopID: "stop-1"
        )
        let scheduled = OfflineScheduleDeparture(
            id: "scheduled-1",
            lineName: "16",
            destination: "Airport",
            departureDate: Date(timeIntervalSince1970: 1_800),
            platform: nil,
            mode: .bus
        )
        let model = StopDetailPresentationModel(
            stop: stop,
            routes: [],
            departures: [],
            offlineScheduledDepartures: [scheduled],
            alerts: [],
            availablePlatforms: [],
            selectedLine: nil,
            selectedPlatform: nil,
            isLoadingDepartures: false,
            errorMessage: nil,
            lastUpdated: nil,
            isStale: false,
            isFavourite: false,
            trackedDepartureId: nil,
            liveActivityErrorMessage: nil,
            liveActivityStaleMessage: "",
            activeReminder: nil,
            departureReminderErrorMessage: nil
        )

        #expect(model.mergedDepartures.isEmpty)
        #expect(model.scheduledDepartures.map(\.id) == ["scheduled-1"])
        #expect(model.scheduledDepartures.first?.dataSource == .gtfs)
    }
}
