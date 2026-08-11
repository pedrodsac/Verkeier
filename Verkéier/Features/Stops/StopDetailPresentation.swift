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

    var mergedDepartures: [Departure] {
        guard let stop else { return departures }
        let merged = DepartureBoardMerger.merge(
            live: departures,
            scheduled: offlineScheduledDepartures,
            stopID: stop.id
        )

        let lineFiltered: [Departure]
        if let selectedLine,
           let route = routes.first(where: { $0.id == selectedLine }) {
            lineFiltered = merged.filter { departure in
                departure.routeId?.caseInsensitiveCompare(route.id) == .orderedSame
                    || departure.lineName.caseInsensitiveCompare(route.shortName) == .orderedSame
            }
        } else {
            lineFiltered = merged
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
    }
}
