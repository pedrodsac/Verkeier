import Foundation

struct StopDetailPresentationModel {
    let stop: Stop?
    let routes: [TransitRoute]
    let departures: [Departure]
    let offlineScheduledDepartures: [OfflineScheduleDeparture]
    let alerts: [AlertMessage]
    let availablePlatforms: [String]
    let selectedLine: String?
    let selectedPlatform: String?
    let departureBoardFilter: TransitBoardFilter
    let isLoadingDepartures: Bool
    let errorMessage: String?
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
        availablePlatforms: [String],
        selectedLine: String?,
        selectedPlatform: String?,
        departureBoardFilter: TransitBoardFilter = TransitBoardFilter(),
        isLoadingDepartures: Bool,
        errorMessage: String?,
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
        self.availablePlatforms = availablePlatforms
        self.selectedLine = selectedLine
        self.selectedPlatform = selectedPlatform
        self.departureBoardFilter = departureBoardFilter
        self.isLoadingDepartures = isLoadingDepartures
        self.errorMessage = errorMessage
        self.lastUpdated = lastUpdated
        self.isStale = isStale
        self.isFavourite = isFavourite
        self.trackedDepartureId = trackedDepartureId
        self.liveActivityErrorMessage = liveActivityErrorMessage
        self.liveActivityStaleMessage = liveActivityStaleMessage
        self.activeReminder = activeReminder
        self.departureReminderErrorMessage = departureReminderErrorMessage
    }

    var mergedDepartures: [Departure] {
        let lineFiltered: [Departure]
        if let selectedLine,
           let route = routes.first(where: { $0.id == selectedLine }) {
            lineFiltered = departures.filter { departure in
                departure.routeId?.caseInsensitiveCompare(route.id) == .orderedSame
                    || departure.lineName.caseInsensitiveCompare(route.shortName) == .orderedSame
            }
        } else {
            lineFiltered = departures
        }

        guard let selectedPlatform else { return lineFiltered }
        return lineFiltered.filter { $0.platform == selectedPlatform }
    }
}

/// Callbacks the stop-detail sheet needs, sliced from ``TransitSheetActions``.
struct StopDetailActions {
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
        startTrackingDeparture = actions.startTrackingDeparture
        stopTrackingDeparture = actions.stopTrackingDeparture
        scheduleDepartureReminder = actions.scheduleDepartureReminder
        cancelDepartureReminder = actions.cancelDepartureReminder
        toggleDepartureLine = actions.toggleDepartureLine
        selectDeparturePlatform = actions.selectDeparturePlatform
        updateDepartureBoardFilter = actions.updateDepartureBoardFilter
    }
}
