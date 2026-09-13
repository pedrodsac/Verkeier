import AppIntents
import Foundation

struct ShowNearbyStopsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Nearby Stops"
    static let description = IntentDescription("Open Verkéier to nearby public transport stops.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        TransitIntentHandoff.save(.showNearbyStops)
        return .result(dialog: "Opening nearby stops.")
    }
}

struct OpenFavouriteStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Favourite Stop"
    static let description = IntentDescription("Open Verkéier to a saved favourite stop.")
    static let openAppWhenRun = true

    @Parameter(title: "Stop")
    var stop: FavouriteStopEntity

    func perform() async throws -> some IntentResult {
        TransitIntentHandoff.save(.openFavouriteStop(stopId: stop.id))
        return .result(dialog: "Opening \(stop.name).")
    }
}

struct TrackNextDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "Track Next Departure"
    static let description = IntentDescription("Open Verkéier to track the next departure from a favourite stop.")
    static let openAppWhenRun = true

    @Parameter(title: "Stop")
    var stop: FavouriteStopEntity

    func perform() async throws -> some IntentResult {
        TransitIntentHandoff.save(.trackNextDeparture(stopId: stop.id))
        return .result(dialog: "Opening departure tracking.")
    }
}

struct PlanRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan Route"
    static let description = IntentDescription("Open Verkéier route planning for a destination.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destinationName: String

    func perform() async throws -> some IntentResult {
        TransitIntentHandoff.save(.planRoute(destinationName: destinationName))
        return .result(dialog: "Opening route planning.")
    }
}

struct GetNextDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Next Departures"
    static let description = IntentDescription("Show the next departures for a favourite stop.")

    @Parameter(title: "Stop")
    var stop: FavouriteStopEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        guard let board = SharedTransitDataStore.favouriteDepartureBoards()[stop.id] else {
            return .result(dialog: IntentDialog(stringLiteral: "No saved departure board is available for \(stop.name) yet. Open Verkéier to refresh it."))
        }

        let freshness = boardFreshness(board, now: now)
        let next = board.departures
            .filter { departure in
                guard let date = departure.displayDepartureDate else { return false }
                return SharedDepartureTiming.isVisible(date, at: now) && !departure.isCancelled
            }
            .sorted {
                ($0.displayDepartureDate ?? .distantFuture) < ($1.displayDepartureDate ?? .distantFuture)
            }
            .first

        guard let next, let date = next.displayDepartureDate else {
            return .result(dialog: IntentDialog(stringLiteral: "There are no upcoming departures in the latest saved board for \(stop.name). \(freshness)"))
        }
        let departureTime = date.formatted(date: .omitted, time: .shortened)
        return .result(dialog: IntentDialog(stringLiteral: "Next from \(stop.name): \(next.lineName) to \(next.destination) at \(departureTime). \(freshness)"))
    }

    private func boardFreshness(_ board: SharedDepartureBoard, now: Date) -> String {
        let source = board.sourceSummary ?? "Transit data"
        let age = now.timeIntervalSince(board.updatedAt)
        if age > 15 * 60 {
            return "This \(source) board is stale; it was saved at \(board.updatedAt.formatted(date: .omitted, time: .shortened))."
        }
        return "Source: \(source), refreshed at \(board.updatedAt.formatted(date: .omitted, time: .shortened))."
    }
}

struct VerkéierShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowNearbyStopsIntent(),
            phrases: [
                "Show nearby stops in \(.applicationName)",
                "Open nearby stops in \(.applicationName)"
            ],
            shortTitle: "Nearby Stops",
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: PlanRouteIntent(),
            phrases: [
                "Plan a route with \(.applicationName)"
            ],
            shortTitle: "Plan Route",
            systemImageName: "arrow.triangle.turn.up.right.diamond"
        )

        AppShortcut(
            intent: OpenFavouriteStopIntent(),
            phrases: [
                "Open a favourite stop in \(.applicationName)",
                "Show my favourite stop in \(.applicationName)"
            ],
            shortTitle: "Open Stop",
            systemImageName: "star.fill"
        )

        AppShortcut(
            intent: TrackNextDepartureIntent(),
            phrases: [
                "Track the next departure with \(.applicationName)",
                "Start departure tracking in \(.applicationName)"
            ],
            shortTitle: "Track Departure",
            systemImageName: "livephoto"
        )

        AppShortcut(
            intent: GetNextDeparturesIntent(),
            phrases: [
                "Get next departures with \(.applicationName)"
            ],
            shortTitle: "Departures",
            systemImageName: "clock.fill"
        )
    }
}
