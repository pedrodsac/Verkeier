import Foundation
import Testing

@testable import Verkeier

struct StopDepartureSourceTests {
    @Test func liveBoardExcludesGTFSRowsAndPlatforms() {
        let model = makeModel(liveDepartures: [live], useOfflineFallback: false)

        #expect(model.displayedDepartures.map(\.id) == ["live"])
        #expect(model.availablePlatforms == ["1"])
        #expect(model.scheduledDepartures.isEmpty)
        #expect(!model.isShowingScheduledFallback)
    }

    @Test func emptyLiveBoardDoesNotFillFromGTFS() {
        let model = makeModel(liveDepartures: [], useOfflineFallback: false)

        #expect(model.displayedDepartures.isEmpty)
        #expect(model.availablePlatforms.isEmpty)
        #expect(!model.isShowingScheduledFallback)
    }

    @Test func failedLiveBoardUsesGTFSFallback() {
        let model = makeModel(liveDepartures: [], useOfflineFallback: true)

        #expect(model.displayedDepartures.map(\.id) == ["gtfs"])
        #expect(model.availablePlatforms == ["2"])
        #expect(model.isShowingScheduledFallback)
    }

    private let departureDate = Date(timeIntervalSince1970: 1_800_000_000)

    private var live: Departure {
        Departure(
            id: "live",
            stopId: "stop",
            lineName: "16",
            destination: "Gare",
            scheduledDeparture: departureDate,
            platform: "1",
            dataSource: .atpOpenAPI
        )
    }

    private func makeModel(
        liveDepartures: [Departure],
        useOfflineFallback: Bool
    ) -> StopDetailPresentationModel {
        StopDetailPresentationModel(
            stop: Stop(
                id: "stop",
                name: "Central",
                location: LocationPoint(latitude: 49.61, longitude: 6.13),
                dataSource: .mock
            ),
            routes: [],
            departures: liveDepartures,
            offlineScheduledDepartures: [OfflineScheduleDeparture(
                id: "gtfs",
                lineName: "18",
                destination: "Kirchberg",
                departureDate: departureDate.addingTimeInterval(300),
                platform: "2",
                mode: .bus
            )],
            isUsingOfflineDepartures: useOfflineFallback,
            alerts: [],
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
    }
}
