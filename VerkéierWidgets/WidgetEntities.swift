import AppIntents
import Foundation
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
    func entities(for identifiers: [String]) async throws -> [WidgetFavouriteStopEntity] {
        entities.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFavouriteStopEntity] {
        entities
    }

    func defaultResult() async -> WidgetFavouriteStopEntity? {
        entities.first
    }

    private var entities: [WidgetFavouriteStopEntity] {
        SharedTransitDataStore.favouriteStops().map {
            WidgetFavouriteStopEntity(id: $0.id, name: $0.name, locality: $0.locality)
        }
    }
}

struct SelectFavouriteStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Favourite Stop"
    static let description = IntentDescription("Choose the stop shown by Live Departures.")

    @Parameter(title: "Stop")
    var stop: WidgetFavouriteStopEntity?
}

struct RefreshDeparturesWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Departures"
    static let description = IntentDescription("Refresh the departures shown in the widget.")

    @Parameter(title: "Stop ID")
    var stopID: String?

    init() {}

    init(stopID: String?) {
        self.stopID = stopID
    }

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: DeparturesSummaryWidget.kind)
        return .result()
    }
}

struct LiveDeparturesEntry: TimelineEntry {
    let date: Date
    let stop: SharedFavouriteStop?
    let board: SharedDepartureBoard?

    var departures: [SharedWidgetDeparture] {
        return (board?.departures ?? [])
            .filter { departure in
                guard let stop else { return true }
                return !departure.destination.identifiesSameStation(as: stop.name)
            }
            .filter {
                ($0.displayDepartureDate)
                    .map { SharedDepartureTiming.isVisible($0, at: date) } ?? true
            }
            .sorted {
                ($0.displayDepartureDate ?? .distantFuture) < ($1.displayDepartureDate ?? .distantFuture)
            }
    }

    var isStale: Bool {
        guard let board else { return false }
        return date.timeIntervalSince(board.updatedAt) > 15 * 60
    }

    var updateLabel: String {
        guard let board else { return "Waiting for live data" }
        if isStale {
            return "Last updated \(board.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Updated \(board.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    var destinationURL: URL {
        stop.map { TransitDeepLink.showDepartures(stopId: $0.id).url }
            ?? TransitDeepLink.showNearbyStops.url
    }
}

struct LiveDeparturesTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> LiveDeparturesEntry {
        LiveDeparturesEntry(
            date: .now,
            stop: SharedFavouriteStop(id: "preview", name: "Hamilius", locality: "Centre"),
            board: SharedDepartureBoard(
                stopId: "preview",
                departures: [
                    SharedWidgetDeparture(
                        id: "preview-1",
                        lineName: "16",
                        destination: "Findel, Airport",
                        scheduledDeparture: .now.addingTimeInterval(4 * 60),
                        realtimeDeparture: .now.addingTimeInterval(5 * 60),
                        delayMinutes: 1,
                        platform: "2",
                        isCancelled: false
                    ),
                    SharedWidgetDeparture(
                        id: "preview-2",
                        lineName: "T1",
                        destination: "Luxexpo",
                        scheduledDeparture: .now.addingTimeInterval(8 * 60),
                        realtimeDeparture: nil,
                        delayMinutes: nil,
                        platform: "1",
                        isCancelled: false
                    )
                ],
                updatedAt: .now
            )
        )
    }

    func snapshot(
        for configuration: SelectFavouriteStopIntent,
        in context: Context
    ) async -> LiveDeparturesEntry {
        if context.isPreview { return placeholder(in: context) }
        return entry(for: configuration, at: .now)
    }

    func timeline(
        for configuration: SelectFavouriteStopIntent,
        in _: Context
    ) async -> Timeline<LiveDeparturesEntry> {
        let start = Date.now
        let entries = (0...15).map {
            entry(for: configuration, at: start.addingTimeInterval(TimeInterval($0 * 60)))
        }
        return Timeline(entries: entries, policy: .after(start.addingTimeInterval(15 * 60)))
    }

    private func entry(
        for configuration: SelectFavouriteStopIntent,
        at date: Date
    ) -> LiveDeparturesEntry {
        let stops = SharedTransitDataStore.favouriteStops()
        let stop = configuration.stop.flatMap { selected in
            stops.first { $0.id == selected.id }
        } ?? stops.first
        let board = stop.flatMap { SharedTransitDataStore.favouriteDepartureBoards()[$0.id] }
        return LiveDeparturesEntry(date: date, stop: stop, board: board)
    }
}
