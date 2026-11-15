import Foundation
import MobiliteitKit

/// Fetches a favourite stop's live departures from the widget extension, so
/// the widget stays current while the app is closed.
///
/// The fetched board replaces the one the app last saved in the App Group.
/// When a fetch is not possible (no relay configured, no live identifier, or
/// a network failure) the saved board is kept and the widget shows it as
/// stale once it ages.
nonisolated struct WidgetDepartureRefresher: Sendable {
    /// Boards newer than this are reused rather than fetched again. The app
    /// refreshes favourites every 45 seconds while open, and ATP's quota is
    /// shared with it.
    static let minimumRefreshInterval: TimeInterval = 30

    /// The board window. The widget shows three rows, so it needs far less
    /// than the app's 24-hour board, and a short window keeps the response
    /// within the extension's memory limit.
    static let boardWindowMinutes = 180

    static let sourceLabel = "mobiliteit.lu OpenAPI"

    let proxyURL: URL
    let session: URLSession

    /// The refresher for the relay in the extension's Info.plist, or `nil`
    /// when the build has no relay configured.
    static func configured() -> WidgetDepartureRefresher? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "API_PROXY_URL") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return WidgetDepartureRefresher(proxyURL: url, session: URLSession(configuration: configuration))
    }

    static func needsRefresh(_ board: SharedDepartureBoard?, at date: Date = .now) -> Bool {
        guard let board else { return true }
        return date.timeIntervalSince(board.updatedAt) >= minimumRefreshInterval
    }

    /// Fetches and saves the stop's board when the saved one is older than
    /// ``minimumRefreshInterval``, then returns the board to show.
    @discardableResult
    func refreshIfNeeded(_ stop: SharedFavouriteStop) async -> SharedDepartureBoard? {
        let saved = SharedTransitDataStore.favouriteDepartureBoards()[stop.id]
        guard Self.needsRefresh(saved) else { return saved }
        do {
            let board = try await fetchBoard(for: stop)
            SharedTransitDataStore.saveFavouriteDepartureBoard(
                stopId: stop.id,
                departures: board.departures,
                updatedAt: board.updatedAt,
                sourceSummary: board.sourceSummary
            )
            return board
        } catch {
            return saved
        }
    }

    func fetchBoard(for stop: SharedFavouriteStop) async throws -> SharedDepartureBoard {
        guard let stationID = stop.liveStationID else { throw RefreshError.noLiveIdentifier }
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let client = MobiliteitAPIClient(
            apiKey: "",
            baseURL: proxyURL.appendingPathComponent("atp"),
            session: session,
            language: language
        )
        let snapshot = try await client.departureBoardSnapshot(
            HafasDepartureBoardRequest(
                stationID: stationID,
                language: language,
                durationMinutes: Self.boardWindowMinutes,
                maximumJourneys: -1,
                realtimeMode: .serverDefault,
                // The pass list identifies terminal arrivals to leave out.
                includePasslist: true
            )
        )
        let departures = snapshot.board.departures.values
            .compactMap { Self.departure(from: $0, stop: stop) }
            .sorted { ($0.displayDepartureDate ?? .distantFuture) < ($1.displayDepartureDate ?? .distantFuture) }
        return SharedDepartureBoard(
            stopId: stop.id,
            departures: departures,
            updatedAt: snapshot.fetchedAt,
            sourceSummary: departures.isEmpty ? nil : Self.sourceLabel
        )
    }

    /// Maps an ATP row the way the app's live board does, keeping only what
    /// the widget shows.
    static func departure(from source: HafasDeparture, stop: SharedFavouriteStop) -> SharedWidgetDeparture? {
        let identifiers = [stop.id, stop.liveStationID].compactMap { $0 }
        if HafasDepartureReading.isTerminalArrival(source, stopIdentifiers: identifiers, stopName: stop.name) {
            return nil
        }
        let scheduled = HafasDepartureReading.scheduledDate(of: source)
        let realtime = HafasDepartureReading.realtimeDate(of: source)
        guard scheduled != nil || realtime != nil else { return nil }

        let lineName = HafasDepartureReading.lineName(of: source)
        let destination = HafasDepartureReading.destination(of: source)
        let delay = scheduled.flatMap { planned in
            realtime.map { Int(($0.timeIntervalSince(planned) / 60).rounded()) }
        }
        let journeyID = source.journeyReference?.reference
        let generatedID = [
            stop.id, journeyID ?? "", lineName, destination, source.plannedDate ?? "", source.plannedTime ?? "",
        ]
        .joined(separator: "|")

        return SharedWidgetDeparture(
            id: journeyID ?? generatedID,
            lineName: lineName,
            destination: destination,
            scheduledDeparture: scheduled,
            realtimeDeparture: realtime,
            delayMinutes: delay,
            platform: HafasDepartureReading.platform(of: source),
            isCancelled: source.cancelled ?? false,
            sourceLabel: sourceLabel,
            lineKind: HafasDepartureReading.lineKind(productClass: source.product?.productClass)
        )
    }

    enum RefreshError: Error {
        case noLiveIdentifier
    }
}
