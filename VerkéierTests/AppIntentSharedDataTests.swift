import Foundation
import Testing

@testable import Verkeier

struct AppIntentSharedDataTests {
    @Test func handoffRoundTripsAndConsumesOnce() {
        let store = makeHandoffStore()
        _ = TransitIntentHandoff.consumePending(from: store)

        TransitIntentHandoff.save(.planRoute(destinationName: "Hill Lift"), store: store)

        #expect(
            TransitIntentHandoff.consumePending(from: store)
                == .planRoute(destinationName: "Hill Lift")
        )
        #expect(TransitIntentHandoff.consumePending(from: store) == nil)
    }

    @Test func favouriteStopEntitiesMirrorSharedFavouriteStops() throws {
        clearSharedStorage()
        defer { clearSharedStorage() }

        let stop = Stop(
            id: "stop-1",
            name: "Hill Lift",
            locality: "Test City",
            location: LocationPoint(name: "Hill Lift", latitude: 49.6116, longitude: 6.1319),
            modes: [.funicular],
            dataSource: .gtfs,
            platformIds: ["platform-1", "platform-2"]
        )

        FavouriteStopEntityStore.save(stops: [stop])

        let entity = try #require(FavouriteStopEntityStore.entities().first)
        #expect(entity.id == "stop-1")
        #expect(entity.name == "Hill Lift")
        #expect(entity.locality == "Test City")
        #expect(entity.platformIds == ["platform-1", "platform-2"])
        #expect(SharedTransitDataStore.favouriteStops().first?.name == "Hill Lift")
        #expect(SharedTransitDataStore.favouriteStops().first?.platformIds == ["platform-1", "platform-2"])
    }

    @Test func sharedFavouriteStopsDefaultPlatformIdsWhenMissingFromStoredJSON() throws {
        let data = Data(
            """
            [
              {
                "id": "stop-1",
                "name": "Hill Lift",
                "locality": "Test City"
              }
            ]
            """.utf8
        )

        let stops = try JSONDecoder().decode([SharedFavouriteStop].self, from: data)

        #expect(stops.first?.platformIds == ["stop-1"])
    }

    @Test func persistedFavouriteStopsRoundTripPlatformIds() {
        let stop = Stop(
            id: "grouped-stop",
            name: "Badanstalt",
            locality: "Centre",
            location: LocationPoint(name: "Badanstalt", latitude: 49.6135, longitude: 6.1292),
            modes: [.bus],
            dataSource: .atpOpenAPI,
            platformIds: ["300362001", "300362002"]
        )

        let persisted = PersistedFavouriteStop(stop: stop)
        let restored = persisted.stop

        #expect(restored.id == "grouped-stop")
        #expect(restored.platformIds == ["300362001", "300362002"])
    }

    @Test func deepLinksRoundTripToIntentHandoff() throws {
        let stopURL = TransitDeepLink.openStop(id: "stop 1").url
        let routeURL = TransitDeepLink.planRoute(destinationName: "Hill Lift").url

        #expect(TransitDeepLink(url: TransitDeepLink.showNearbyStops.url) == .showNearbyStops)
        #expect(TransitDeepLink(url: stopURL) == .openStop(id: "stop 1"))
        #expect(TransitDeepLink(url: routeURL) == .planRoute(destinationName: "Hill Lift"))
        #expect(
            TransitIntentHandoff(TransitDeepLink.showDepartures(stopId: "stop-1"))
                == .trackNextDeparture(stopId: "stop-1")
        )
    }

    @Test func nextDeparturesSummaryFormatsUpcomingDepartures() {
        let stop = FavouriteStopEntity(id: "stop-1", name: "Hill Lift", locality: "Test City")
        let now = Date(timeIntervalSince1970: 1_000)
        let departures = [
            Departure(
                id: "later",
                stopId: stop.id,
                lineName: "F2",
                destination: "Lower Station",
                scheduledDeparture: now.addingTimeInterval(360),
                realtimeDeparture: now.addingTimeInterval(420),
                delayMinutes: 1,
                dataSource: .atpOpenAPI
            ),
            Departure(
                id: "first",
                stopId: stop.id,
                lineName: "F1",
                destination: "Upper Station",
                scheduledDeparture: now.addingTimeInterval(120),
                realtimeDeparture: now.addingTimeInterval(120),
                delayMinutes: 0,
                dataSource: .atpOpenAPI
            ),
        ]

        let summary = NextDeparturesIntentService.summary(
            for: stop,
            departures: departures,
            now: now
        )

        #expect(
            summary
                == "Next departures from Hill Lift: F1 to Upper Station, in 2 min, On time; F2 to Lower Station, in 7 min, +1 min"
        )
    }

    @Test func nextDeparturesSummaryHandlesEmptyBoard() {
        let stop = FavouriteStopEntity(id: "stop-1", name: "Hill Lift", locality: "Test City")

        #expect(
            NextDeparturesIntentService.summary(for: stop, departures: [], now: .now)
                == "No upcoming live departures are available for Hill Lift."
        )
    }

    @Test func trackedDepartureReminderRoundTripsSharedStorage() throws {
        clearSharedStorage()
        defer { clearSharedStorage() }

        let reminder = SharedTrackedDepartureReminder(
            departureId: "dep-1",
            stopId: "stop-1",
            stopName: "Hamilius",
            lineName: "16",
            destination: "Kirchberg",
            scheduledDeparture: Date(timeIntervalSince1970: 1_200),
            realtimeDeparture: Date(timeIntervalSince1970: 1_260),
            delayMinutes: 1,
            isCancelled: false,
            leadTimeMinutes: 5,
            notifiedDelayMinutes: 1,
            didNotifyCancellation: false,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )

        SharedTransitDataStore.saveTrackedReminder(reminder)

        let restored = try #require(SharedTransitDataStore.trackedReminder())
        #expect(restored.departureId == "dep-1")
        #expect(restored.stopName == "Hamilius")
        #expect(restored.leadTimeMinutes == 5)
        #expect(restored.notifiedDelayMinutes == 1)
        #expect(restored.didNotifyCancellation == false)
    }

    private func clearSharedStorage() {
        SharedTransitDataStore.userDefaults.removeObject(
            forKey: SharedTransitDataStore.favouriteStopsKey)
        UserDefaults.standard.removeObject(forKey: SharedTransitDataStore.favouriteStopsKey)
        SharedTransitDataStore.userDefaults.removeObject(
            forKey: SharedTransitDataStore.trackedDepartureReminderKey)
        UserDefaults.standard.removeObject(forKey: SharedTransitDataStore.trackedDepartureReminderKey)
    }

    private func makeHandoffStore() -> TransitIntentHandoffStore {
        let suiteName = "AppIntentSharedDataTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return TransitIntentHandoffStore(defaults: defaults)
    }
}
