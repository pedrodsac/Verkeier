import Foundation
import Testing

@testable import Verkeier

@MainActor
struct FavouritesPresentationTests {
    @Test func legacyLabelFallsBackAndNewLabelsAreNormalized() {
        let favourite = PersistedFavouriteStop(stop: makeStop(id: "home"))
        favourite.label = " Home "

        #expect(favourite.labels == ["Home"])

        favourite.replaceLabels(with: [" Home ", "work", "WORK", "Caf\u{00E9}", "cafe\u{0301}", ""])

        #expect(favourite.labels == ["Home", "work", "Caf\u{00E9}"])
        #expect(favourite.label == "Home")
    }

    @Test func stopAppearsInEveryAssignedLabelSection() {
        let homeWork = FavouriteStopPresentationModel(
            stop: makeStop(id: "one"),
            labels: ["Home", "Work"],
            departures: FavouriteDepartureBoardSnapshot()
        )
        let unlabelled = FavouriteStopPresentationModel(
            stop: makeStop(id: "two"),
            labels: [],
            departures: FavouriteDepartureBoardSnapshot()
        )
        let model = FavouritesPresentationModel(
            stops: [homeWork, unlabelled],
            isRefreshing: false,
            liveDeparturesAvailable: true
        )

        let sections = model.labelSections()

        #expect(sections.map(\.title) == ["Home", "Work", "Saved Stops"])
        #expect(sections.first { $0.title == "Home" }?.stops.map(\.id) == ["one"])
        #expect(sections.first { $0.title == "Work" }?.stops.map(\.id) == ["one"])
        #expect(sections.first { $0.title == "Saved Stops" }?.stops.map(\.id) == ["two"])
    }

    @Test func staleSnapshotRetainsPreviousDeparturesAfterFailure() {
        let date = Date.now.addingTimeInterval(-91)
        let snapshot = FavouriteDepartureBoardSnapshot(
            phase: .failed,
            departures: [makeDeparture()],
            lastUpdated: date,
            errorMessage: "Favourite departures could not be loaded."
        )

        #expect(snapshot.hasPreviousContent)
        #expect(snapshot.isStale(now: .now))
        #expect(snapshot.departures.count == 1)
    }

    @Test func allSavedStopsRemainAvailableRegardlessOfLabels() {
        let homeStop = FavouriteStopPresentationModel(
            stop: makeStop(id: "home"),
            labels: ["Home"],
            departures: FavouriteDepartureBoardSnapshot()
        )
        let workshopStop = FavouriteStopPresentationModel(
            stop: makeStop(id: "workshop"),
            labels: ["Workshop"],
            departures: FavouriteDepartureBoardSnapshot()
        )
        let model = FavouritesPresentationModel(
            stops: [homeStop, workshopStop],
            isRefreshing: false,
            liveDeparturesAvailable: true
        )

        #expect(model.stops.map(\.id) == ["home", "workshop"])
        #expect(model.labelSections().flatMap(\.stops).map(\.id).sorted() == ["home", "workshop"])
    }

    private func makeStop(id: String) -> Stop {
        Stop(
            id: id,
            name: "Stop \(id)",
            location: LocationPoint(latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: .gtfs
        )
    }

    private func makeDeparture() -> Departure {
        Departure(
            id: "departure",
            stopId: "one",
            lineName: "16",
            destination: "Kirchberg",
            scheduledDeparture: .now.addingTimeInterval(300),
            dataSource: .atpOpenAPI
        )
    }
}
