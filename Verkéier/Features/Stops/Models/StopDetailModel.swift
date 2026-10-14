import Foundation
import Observation

/// The selected stop and its departure board.
@MainActor @Observable
final class StopDetailModel {
    var selectedStop: Stop?
    var selectedStopRoutes: [TransitRoute] = []

    var departures: [Departure] = []
    var offlineScheduledDepartures: [OfflineScheduleDeparture] = []
    var isUsingOfflineDepartures = false
    var isLoadingDepartures = false
    var departuresErrorMessage: String?
    var departuresLastUpdated: Date?

    var selectedDepartureLine: String?
    var selectedDeparturePlatform: String?
    /// Query controls for the selected stop's live board. Saved with a stop
    /// when it becomes a favourite.
    var departureBoardFilter = TransitBoardFilter()

    /// Every departure request receives a generation. A response may publish
    /// only while it remains the most recent request for the selected stop.
    @ObservationIgnored private var departureLoadGeneration = 0
    @ObservationIgnored private var departureBoardCache = StopDepartureBoardCache()
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    /// Cache only board inputs. Location fixes, route results, and loading-state
    /// changes must not repeat departure normalization and sorting.
    var departureBoardPresentation: StopDepartureBoardPresentation {
        departureBoardCache.presentation(
            for: .init(
                stopID: selectedStop?.id ?? "",
                routes: selectedStopRoutes,
                liveDepartures: departures,
                scheduledDepartures: offlineScheduledDepartures,
                useScheduledFallback: isUsingOfflineDepartures,
                selectedLine: selectedDepartureLine,
                selectedPlatform: selectedDeparturePlatform
            )
        )
    }

    var areDeparturesStale: Bool {
        guard let departuresLastUpdated else { return false }
        return Date().timeIntervalSince(departuresLastUpdated) > 90
    }
}

// MARK: - Selection

extension StopDetailModel {
    /// Shows `stop` with an empty board and cancels any board still loading.
    func select(_ stop: Stop) {
        selectedStop = stop
        selectedStopRoutes = []
        departures = []
        offlineScheduledDepartures = []
        isUsingOfflineDepartures = false
        isLoadingDepartures = false
        departureLoadGeneration &+= 1
        selectedDepartureLine = nil
        selectedDeparturePlatform = nil
        departureBoardFilter = TransitBoardFilter()
        departuresErrorMessage = nil
        departuresLastUpdated = nil
    }

    /// Clears the selected stop and cancels any board still loading.
    func clearSelection() {
        selectedStop = nil
        isLoadingDepartures = false
        departureLoadGeneration &+= 1
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        if selectedDepartureLine == route.id {
            selectedDepartureLine = nil
        } else {
            selectedDepartureLine = route.id
        }

        selectedDeparturePlatform = nil
    }

    func selectDeparturePlatform(_ platform: String?) {
        selectedDeparturePlatform = platform
    }
}

// MARK: - Loading

extension StopDetailModel {
    func loadDepartures(
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService
    ) async {
        guard let selectedStop else { return }
        let selectedStopID = selectedStop.id
        departureLoadGeneration &+= 1
        let requestGeneration = departureLoadGeneration
        isLoadingDepartures = true
        departuresErrorMessage = nil
        isUsingOfflineDepartures = false

        let boardStop = await liveTransitService.resolvedStop(
            for: selectedStop,
            gtfsService: gtfsService
        )
        guard !Task.isCancelled else {
            if isCurrentDepartureRequest(requestGeneration, for: selectedStopID) {
                isLoadingDepartures = false
            }
            return
        }
        guard isCurrentDepartureRequest(requestGeneration, for: selectedStopID) else { return }
        if boardStop != selectedStop {
            self.selectedStop = boardStop
        }

        let liveDepartures: [Departure]
        let fetchedAt: Date?
        let scheduledDepartures: [OfflineScheduleDeparture]
        let liveError: Error?
        do {
            let board = try await liveTransitService.departureBoardSnapshot(
                for: boardStop,
                filter: departureBoardFilter
            )
            liveDepartures = board.departures
            fetchedAt = board.fetchedAt
            scheduledDepartures = []
            liveError = nil
        } catch {
            liveDepartures = []
            fetchedAt = nil
            scheduledDepartures = await gtfsService.scheduledDepartures(
                for: boardStop,
                at: now(),
                limit: .max
            )
            liveError = error
        }

        guard !Task.isCancelled else {
            if isCurrentDepartureRequest(requestGeneration, for: boardStop.id) {
                isLoadingDepartures = false
            }
            return
        }
        guard isCurrentDepartureRequest(requestGeneration, for: boardStop.id) else { return }

        departures = liveDepartures
        offlineScheduledDepartures = scheduledDepartures
        isUsingOfflineDepartures = liveError != nil
        departuresLastUpdated = fetchedAt
        departuresErrorMessage =
            liveError != nil && scheduledDepartures.isEmpty
            ? "No live or offline departures are available for this stop."
            : nil
        isLoadingDepartures = false
    }

    func updateSelectedStopRoutes(using gtfsService: any GTFSService) async {
        guard let selectedStop else {
            selectedStopRoutes = []
            return
        }
        let routes = await gtfsService.routes(for: selectedStop)
        guard self.selectedStop?.id == selectedStop.id else { return }
        selectedStopRoutes = routes.isEmpty ? liveRoutesFromDepartures(for: selectedStop) : routes
    }

    private func isCurrentDepartureRequest(_ generation: Int, for stopID: String) -> Bool {
        departureLoadGeneration == generation && selectedStop?.id == stopID
    }

    /// Keep the line chips useful when the static feed is unavailable or has
    /// no active service for the current date. The live board already carries
    /// the public line and route identifiers, so it is a safe presentation
    /// fallback until GTFS route metadata becomes available.
    private func liveRoutesFromDepartures(for stop: Stop) -> [TransitRoute] {
        var seen: Set<String> = []
        return departures.compactMap { departure in
            let shortName = departure.lineName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortName.isEmpty else { return nil }
            let id =
                departure.routeId?.isEmpty == false
                ? departure.routeId!
                : "atp:\(shortName.normalizedForSearch)"
            guard seen.insert(id).inserted else { return nil }
            return TransitRoute(
                id: id,
                shortName: shortName,
                mode: stop.modes.first ?? .unknown,
                operatorName: departure.operatorName,
                dataSource: .atpOpenAPI
            )
        }
    }
}
