import Foundation

struct CommuteDashboardViewModel {
    let favourites: [Stop]
    let departuresByStopId: [String: [Departure]]
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let expandedStopIds: Set<String>
    let nearby: NearbyStopsPresentationModel
    let activeAlertCount: Int
    /// Time-of-day commute preset to surface at the top of the dashboard, if any.
    var suggestedCommutePreset: RouteCommutePreset?
    /// Recently opened stops, most-recent first.
    var recentStops: [Stop] = []

    var hasFavourites: Bool {
        !favourites.isEmpty
    }

    var statusText: String {
        if isLoadingDepartures && departuresByStopId.isEmpty {
            return "Loading favourite departures"
        }
        guard let lastUpdated else {
            return hasFavourites
                ? "Live departures from favourites" : "Search or pick a nearby stop"
        }
        let formatted = lastUpdated.formatted(date: .omitted, time: .shortened)
        return isStale ? "Stale, last updated \(formatted)" : "Updated \(formatted)"
    }
}

/// Callbacks the commute dashboard needs, sliced from ``TransitSheetActions``.
struct CommuteActions {
    var showAlerts: () -> Void = {}
    var selectStop: (Stop) -> Void = { _ in }
    var toggleExpansion: (String) -> Void = { _ in }
    var applyCommutePreset: (String) -> Void = { _ in }
}

extension CommuteActions {
    init(from actions: TransitSheetActions) {
        self.init()
        showAlerts = actions.showAlerts
        selectStop = actions.selectStop
        toggleExpansion = actions.toggleFavouriteExpansion
        applyCommutePreset = actions.applyCommutePreset
    }
}

/// Callbacks the home sheet needs: its header buttons plus the commute dashboard's.
struct HomeActions {
    var showSearch: () -> Void = {}
    var showSettings: () -> Void = {}
    var commute = CommuteActions()
}

extension HomeActions {
    init(from actions: TransitSheetActions) {
        self.init()
        showSearch = actions.showSearch
        showSettings = actions.showSettings
        commute = CommuteActions(from: actions)
    }
}
