import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct WidgetFavouriteStopEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favourite Stop")
    static let defaultQuery = WidgetFavouriteStopEntityQuery()

    let id: String
    let name: String
    let locality: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: locality.map { "\($0)" }
        )
    }
}

struct WidgetFavouriteStopEntityQuery: EntityQuery {
    func entities(for identifiers: [WidgetFavouriteStopEntity.ID]) async throws
        -> [WidgetFavouriteStopEntity] {
        sharedStops().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFavouriteStopEntity] {
        sharedStops()
    }

    func defaultResult() async -> WidgetFavouriteStopEntity? {
        sharedStops().first
    }

    private func sharedStops() -> [WidgetFavouriteStopEntity] {
        SharedTransitDataStore.favouriteStops().map {
            WidgetFavouriteStopEntity(id: $0.id, name: $0.name, locality: $0.locality)
        }
    }
}

struct SelectFavouriteStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Favourite Stop"
    static let description = IntentDescription("Pick which saved favourite stop this widget opens.")

    @Parameter(title: "Stop")
    var stop: WidgetFavouriteStopEntity?
}

struct FavouriteStopEntry: TimelineEntry {
    let date: Date
    let selectedStop: SharedFavouriteStop?
    let departureBoard: SharedDepartureBoard?
}

struct FavouriteStopTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> FavouriteStopEntry {
        let stop = SharedTransitDataStore.favouriteStops().first
        return FavouriteStopEntry(
            date: .now,
            selectedStop: stop,
            departureBoard: stop.flatMap { SharedTransitDataStore.favouriteDepartureBoards()[$0.id] }
        )
    }

    func snapshot(for configuration: SelectFavouriteStopIntent, in _: Context) async
        -> FavouriteStopEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectFavouriteStopIntent, in _: Context) async
        -> Timeline<FavouriteStopEntry> {
        let entry = entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectFavouriteStopIntent) -> FavouriteStopEntry {
        let stop = selectedStop(from: configuration)
        return FavouriteStopEntry(
            date: .now,
            selectedStop: stop,
            departureBoard: stop.flatMap { SharedTransitDataStore.favouriteDepartureBoards()[$0.id] }
        )
    }

    private func selectedStop(from configuration: SelectFavouriteStopIntent) -> SharedFavouriteStop? {
        let stops = SharedTransitDataStore.favouriteStops()
        if let stopID = configuration.stop?.id {
            return stops.first(where: { $0.id == stopID }) ?? stops.first
        }
        return stops.first
    }
}
