import Foundation
import SwiftData
import Testing

@testable import Verkeier

@MainActor
struct PersistedFavouriteStopTests {
    @Test("Display order puts unnumbered legacy favourites first, then by position")
    func displayOrderSortsLegacyThenPosition() throws {
        let container = try ModelContainer(
            for: PersistedFavouriteStop.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_000)
        context.insert(PersistedFavouriteStop(stop: makeStop("c"), sortOrder: 1, createdAt: base))
        context.insert(PersistedFavouriteStop(stop: makeStop("legacy-new"), createdAt: base.addingTimeInterval(20)))
        context.insert(PersistedFavouriteStop(stop: makeStop("b"), sortOrder: 0, createdAt: base.addingTimeInterval(30)))
        context.insert(PersistedFavouriteStop(stop: makeStop("legacy-old"), createdAt: base.addingTimeInterval(10)))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor(sortBy: PersistedFavouriteStop.displayOrder))
        #expect(fetched.map(\.stopId) == ["legacy-old", "legacy-new", "b", "c"])
    }

    @Test("Applying an order numbers favourites to follow it")
    func applyOrderFollowsStopIDs() {
        let favourites = ["a", "b", "c"].map { PersistedFavouriteStop(stop: makeStop($0)) }

        PersistedFavouriteStop.applyOrder(["c", "a", "b"], to: favourites)

        #expect(favourites.map(\.sortOrder) == [1, 2, 0])
    }

    @Test("Favourites missing from the order keep their relative order at the end")
    func applyOrderKeepsUnlistedAtEnd() {
        let favourites = ["a", "b", "c", "d"].map { PersistedFavouriteStop(stop: makeStop($0)) }

        PersistedFavouriteStop.applyOrder(["d", "b"], to: favourites)

        let ordered = favourites.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }.map(\.stopId)
        #expect(ordered == ["d", "b", "a", "c"])
    }

    @Test("Replacing the stop keeps the look, position and creation date")
    func replaceStopKeepsCustomisation() {
        let createdAt = Date(timeIntervalSince1970: 5_000)
        let favourite = PersistedFavouriteStop(
            stop: makeStop("old", gtfsStopID: "gtfs-old"),
            boardFilter: TransitBoardFilter(),
            sortOrder: 3,
            createdAt: createdAt
        )
        favourite.displayLabel = "Work"
        favourite.colorHex = "#FF453A"
        favourite.iconName = "briefcase.fill"
        favourite.replaceLabels(with: ["Weekdays"])

        favourite.replaceStop(with: makeStop("new", hafasStationIDs: ["200405060"]))

        #expect(favourite.stopId == "new")
        #expect(favourite.stop.name == "Stop new")
        #expect(favourite.stop.gtfsStopID == nil)
        #expect(favourite.stop.hafasStationIDs == ["200405060"])
        #expect(favourite.stop.platformIds == ["new"])
        #expect(favourite.boardFilterData == nil)
        #expect(favourite.displayLabel == "Work")
        #expect(favourite.colorHex == "#FF453A")
        #expect(favourite.iconName == "briefcase.fill")
        #expect(favourite.labels == ["Weekdays"])
        #expect(favourite.sortOrder == 3)
        #expect(favourite.createdAt == createdAt)
    }

    @Test("A name that was just the old stop's name follows the new stop")
    func replaceStopUpdatesDefaultLabel() {
        let old = makeStop("old")
        let favourite = PersistedFavouriteStop(stop: old)
        favourite.displayLabel = old.displayName

        let new = makeStop("new")
        favourite.replaceStop(with: new)

        #expect(favourite.displayLabel == new.displayName)
    }

    private func makeStop(_ id: String, gtfsStopID: String? = nil, hafasStationIDs: [String] = []) -> Stop {
        Stop(
            id: id,
            name: "Stop \(id)",
            location: LocationPoint(latitude: 49.6, longitude: 6.13),
            modes: [.bus],
            dataSource: .gtfs,
            gtfsStopID: gtfsStopID,
            hafasStationIDs: hafasStationIDs
        )
    }
}
