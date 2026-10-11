import AppIntents
import Foundation
import WidgetKit

struct FavouriteStopEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favourite Stop")
    static let defaultQuery = FavouriteStopEntityQuery()

    let id: String
    let name: String
    let locality: String?
    var isTramStop: Bool = false
    let platformIds: [String]
    let boardFilterData: Data?

    nonisolated init(
        id: String,
        name: String,
        locality: String?,
        platformIds: [String]? = nil,
        boardFilterData: Data? = nil
    ) {
        self.id = id
        self.name = name.stationDisplayName
        self.locality = locality
        let ids = (platformIds ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.platformIds = ids.isEmpty ? [id] : ids
        self.boardFilterData = boardFilterData
    }

    var boardFilter: TransitBoardFilter {
        guard let boardFilterData,
              let filter = try? JSONDecoder().decode(TransitBoardFilter.self, from: boardFilterData) else {
            return TransitBoardFilter()
        }
        return filter
    }

    var displayName: String { name.stationDisplayName(hidingLocality: isTramStop) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: (isTramStop ? nil : locality).map { "\($0)" }
        )
    }
}

struct FavouriteStopEntityQuery: EntityQuery {
    func entities(for identifiers: [FavouriteStopEntity.ID]) async throws -> [FavouriteStopEntity] {
        FavouriteStopEntityStore.entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FavouriteStopEntity] {
        FavouriteStopEntityStore.entities()
    }

    func defaultResult() async -> FavouriteStopEntity? {
        FavouriteStopEntityStore.entities().first
    }
}

nonisolated enum FavouriteStopEntityStore {
    nonisolated static func save(stops: [Stop]) {
        let entities = stops.map {
            var shared = SharedFavouriteStop(
                id: $0.id,
                name: $0.name,
                locality: $0.locality,
                platformIds: $0.platformIds
            )
            shared.isTramStop = $0.modes.contains(.tram)
            return shared
        }
        SharedTransitDataStore.saveFavouriteStops(entities)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func save(favourites: [PersistedFavouriteStop]) {
        let entities = favourites.map { favourite in
            var shared = SharedFavouriteStop(
                id: favourite.stopId,
                name: favourite.name,
                locality: favourite.locality,
                platformIds: favourite.stop.platformIds,
                boardFilterData: favourite.boardFilterData
            )
            shared.isTramStop = favourite.stop.modes.contains(.tram)
            return shared
        }
        SharedTransitDataStore.saveFavouriteStops(entities)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func entities() -> [FavouriteStopEntity] {
        SharedTransitDataStore.favouriteStops().map {
            var entity = FavouriteStopEntity(
                id: $0.id,
                name: $0.name,
                locality: $0.locality,
                platformIds: $0.platformIds,
                boardFilterData: $0.boardFilterData
            )
            entity.isTramStop = $0.isTramStop == true
            return entity
        }
    }
}
