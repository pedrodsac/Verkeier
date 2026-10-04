import Foundation

struct StopDetailPresentationModel {
    let stop: Stop?
    let routes: [TransitRoute]
    let departures: [Departure]
    let offlineScheduledDepartures: [OfflineScheduleDeparture]
    let isUsingOfflineDepartures: Bool
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
    private let board: StopDepartureBoardPresentation

    init(
        stop: Stop?,
        routes: [TransitRoute],
        departures: [Departure],
        offlineScheduledDepartures: [OfflineScheduleDeparture],
        isUsingOfflineDepartures: Bool,
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
        departureReminderErrorMessage: String?,
        departureBoard: StopDepartureBoardPresentation? = nil
    ) {
        self.stop = stop
        self.routes = routes
        self.departures = departures
        self.offlineScheduledDepartures = offlineScheduledDepartures
        self.isUsingOfflineDepartures = isUsingOfflineDepartures
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
        self.board = departureBoard ?? StopDepartureBoardPresentation(inputs: .init(
            stopID: stop?.id ?? "",
            routes: routes,
            liveDepartures: departures,
            scheduledDepartures: offlineScheduledDepartures,
            useScheduledFallback: isUsingOfflineDepartures,
            selectedLine: selectedLine,
            selectedPlatform: selectedPlatform
        ))
    }

    var availablePlatforms: [String] { board.availablePlatforms }

    var mergedDepartures: [Departure] {
        board.visibleLiveDepartures
    }

    /// Timetable rows are available only when the live request failed.
    var scheduledDepartures: [Departure] {
        board.visibleScheduledDepartures
    }

    /// A successful live response owns the board, even when it contains no rows.
    var displayedDepartures: [Departure] {
        board.visibleDepartures
    }

    var isShowingScheduledFallback: Bool {
        isUsingOfflineDepartures && !displayedDepartures.isEmpty
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
