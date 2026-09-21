import Foundation

struct StopDetailPresentationModel {
    let stop: Stop?
    let routes: [TransitRoute]
    let departures: [Departure]
    let offlineScheduledDepartures: [OfflineScheduleDeparture]
    let alerts: [AlertMessage]
    let selectedLine: String?
    let selectedPlatform: String?
    let departureBoardFilter: TransitBoardFilter
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let liveErrorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let isFavourite: Bool
    let trackedDepartureId: String?
    let liveActivityErrorMessage: String?
    let liveActivityStaleMessage: String
    let activeReminder: SharedTrackedDepartureReminder?
    let departureReminderErrorMessage: String?

    init(
        stop: Stop?,
        routes: [TransitRoute],
        departures: [Departure],
        offlineScheduledDepartures: [OfflineScheduleDeparture],
        alerts: [AlertMessage],
        selectedLine: String?,
        selectedPlatform: String?,
        departureBoardFilter: TransitBoardFilter = TransitBoardFilter(),
        isLoadingDepartures: Bool,
        errorMessage: String?,
        liveErrorMessage: String? = nil,
        lastUpdated: Date?,
        isStale: Bool,
        isFavourite: Bool,
        trackedDepartureId: String?,
        liveActivityErrorMessage: String?,
        liveActivityStaleMessage: String,
        activeReminder: SharedTrackedDepartureReminder?,
        departureReminderErrorMessage: String?
    ) {
        self.stop = stop
        self.routes = routes
        self.departures = departures
        self.offlineScheduledDepartures = offlineScheduledDepartures
        self.alerts = alerts
        self.selectedLine = selectedLine
        self.selectedPlatform = selectedPlatform
        self.departureBoardFilter = departureBoardFilter
        self.isLoadingDepartures = isLoadingDepartures
        self.errorMessage = errorMessage
        self.liveErrorMessage = liveErrorMessage
        self.lastUpdated = lastUpdated
        self.isStale = isStale
        self.isFavourite = isFavourite
        self.trackedDepartureId = trackedDepartureId
        self.liveActivityErrorMessage = liveActivityErrorMessage
        self.liveActivityStaleMessage = liveActivityStaleMessage
        self.activeReminder = activeReminder
        self.departureReminderErrorMessage = departureReminderErrorMessage
    }

    private var board: DepartureBoardPresentation {
        DepartureBoardPresentation(
            stopID: stop?.id ?? "",
            routes: routes,
            liveDepartures: departures,
            scheduledDepartures: offlineScheduledDepartures,
            selectedLine: selectedLine,
            selectedPlatform: selectedPlatform
        )
    }

    var availablePlatforms: [String] { board.availablePlatforms }

    var mergedDepartures: [Departure] {
        board.visibleLiveDepartures
    }

    /// Timetable rows which are not already represented by the live board.
    ///
    /// HAFAS and GTFS use different IDs for the same journey, so an ID check
    /// alone is not enough. A scheduled time, line, and destination form the
    /// stable rider-facing identity shared by both feeds. The API row always
    /// wins: it carries the live status and is the row users can track.
    var scheduledDepartures: [Departure] {
        board.visibleScheduledDepartures
    }

    /// The one list shown on a stop board: live rows first when a live and
    /// scheduled row describe the same trip, followed by timetable-only rows
    /// in departure-time order.
    var displayedDepartures: [Departure] {
        board.visibleDepartures
    }

    var isShowingScheduledFallback: Bool {
        liveErrorMessage != nil && departures.isEmpty && !displayedDepartures.isEmpty
    }
}

/// Pure source-merging and filtering for a stop departure board.
private struct DepartureBoardPresentation {
    let routes: [TransitRoute]
    let selectedLine: String?
    let selectedPlatform: String?
    let liveDepartures: [Departure]
    let scheduledDepartures: [Departure]

    init(
        stopID: String,
        routes: [TransitRoute],
        liveDepartures: [Departure],
        scheduledDepartures: [OfflineScheduleDeparture],
        selectedLine: String?,
        selectedPlatform: String?
    ) {
        self.routes = routes
        self.selectedLine = selectedLine
        self.selectedPlatform = selectedPlatform
        let uniqueLiveDepartures = Self.unique(liveDepartures)
        self.liveDepartures = uniqueLiveDepartures

        let scheduled = scheduledDepartures.map { departure in
            Departure(
                id: departure.id,
                stopId: stopID,
                lineName: departure.lineName,
                destination: departure.destination,
                scheduledDeparture: departure.departureDate,
                platform: departure.platform,
                dataSource: .gtfs
            )
        }
        self.scheduledDepartures = Self.unique(scheduled).filter { scheduled in
            !uniqueLiveDepartures.contains { live in
                live.representsSameScheduledJourney(as: scheduled)
            }
        }
    }

    var availablePlatforms: [String] {
        var seen: Set<String> = []
        return lineFiltered(liveDepartures + scheduledDepartures)
            .compactMap { departure in
                guard let platform = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !platform.isEmpty,
                      seen.insert(platform).inserted else { return nil }
                return platform
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var visibleLiveDepartures: [Departure] { visible(liveDepartures) }
    var visibleScheduledDepartures: [Departure] { visible(scheduledDepartures) }

    var visibleDepartures: [Departure] {
        (visibleLiveDepartures + visibleScheduledDepartures)
            .enumerated()
            .sorted { lhs, rhs in
                let lhsTime = lhs.element.realtimeDeparture ?? lhs.element.scheduledDeparture ?? .distantFuture
                let rhsTime = rhs.element.realtimeDeparture ?? rhs.element.scheduledDeparture ?? .distantFuture
                return lhsTime == rhsTime ? lhs.offset < rhs.offset : lhsTime < rhsTime
            }
            .map(\.element)
    }

    private func visible(_ departures: [Departure]) -> [Departure] {
        lineFiltered(departures).filter { departure in
            guard let selectedPlatform else { return true }
            return departure.platform == selectedPlatform
        }
    }

    private func lineFiltered(_ departures: [Departure]) -> [Departure] {
        guard let selectedLine,
              let route = routes.first(where: { $0.id == selectedLine }) else {
            return departures
        }
        return departures.filter { departure in
            departure.routeId?.caseInsensitiveCompare(route.id) == .orderedSame
                || departure.lineName.caseInsensitiveCompare(route.shortName) == .orderedSame
        }
    }

    private static func unique(_ departures: [Departure]) -> [Departure] {
        var result: [Departure] = []
        for departure in departures where !result.contains(where: {
            $0.representsSameScheduledJourney(as: departure)
        }) {
            result.append(departure)
        }
        return result
    }
}

private extension Departure {
    /// Live predictions can move, but their planned time identifies the
    /// scheduled service. Accept a one-minute tolerance because the feeds can
    /// disagree on seconds while still describing the same departure.
    func representsSameScheduledJourney(as other: Departure) -> Bool {
        if id == other.id { return true }

        guard lineName.normalizedForSearch == other.lineName.normalizedForSearch,
              destination.normalizedForSearch == other.destination.normalizedForSearch,
              let scheduledDeparture,
              let otherScheduledDeparture = other.scheduledDeparture
        else {
            return false
        }

        return abs(scheduledDeparture.timeIntervalSince(otherScheduledDeparture)) <= 60
    }
}

/// Callbacks the stop-detail sheet needs, sliced from ``TransitSheetActions``.
struct StopDetailActions {
    var showDirections: () -> Void = {}
    var startTrackingDeparture: (Departure) -> Void = { _ in }
    var stopTrackingDeparture: () -> Void = {}
    var scheduleDepartureReminder: (Departure, Int) -> Void = { _, _ in }
    var cancelDepartureReminder: () -> Void = {}
    var toggleDepartureLine: (TransitRoute) -> Void = { _ in }
    var selectDeparturePlatform: (String?) -> Void = { _ in }
    var updateDepartureBoardFilter: (TransitBoardFilter) -> Void = { _ in }
}

extension StopDetailActions {
    init(from actions: TransitSheetActions) {
        self.init()
        showDirections = actions.showDirections
        startTrackingDeparture = actions.startTrackingDeparture
        stopTrackingDeparture = actions.stopTrackingDeparture
        scheduleDepartureReminder = actions.scheduleDepartureReminder
        cancelDepartureReminder = actions.cancelDepartureReminder
        toggleDepartureLine = actions.toggleDepartureLine
        selectDeparturePlatform = actions.selectDeparturePlatform
        updateDepartureBoardFilter = actions.updateDepartureBoardFilter
    }
}
