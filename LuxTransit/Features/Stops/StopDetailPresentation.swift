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
}

/// Callbacks the stop-detail sheet needs, sliced from ``TransitSheetActions``.
struct StopDetailActions {
    var openDirections: () -> Void = {}
    var startTrackingDeparture: (Departure) -> Void = { _ in }
    var stopTrackingDeparture: () -> Void = {}
    var scheduleDepartureReminder: (Departure, Int) -> Void = { _, _ in }
    var cancelDepartureReminder: () -> Void = {}
    var toggleDepartureLine: (TransitRoute) -> Void = { _ in }
    var showLineDetail: (TransitRoute) -> Void = { _ in }
    var selectDeparturePlatform: (String?) -> Void = { _ in }
}

extension StopDetailActions {
    init(from actions: TransitSheetActions) {
        self.init()
        openDirections = actions.showDirections
        startTrackingDeparture = actions.startTrackingDeparture
        stopTrackingDeparture = actions.stopTrackingDeparture
        scheduleDepartureReminder = actions.scheduleDepartureReminder
        cancelDepartureReminder = actions.cancelDepartureReminder
        toggleDepartureLine = actions.toggleDepartureLine
        showLineDetail = actions.showLineDetail
        selectDeparturePlatform = actions.selectDeparturePlatform
    }
}
