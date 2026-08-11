import Foundation

struct CommuteDashboardViewModel {
    let favourites: [Stop]
    let departuresByStopId: [String: [Departure]]
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let nearby: NearbyStopsPresentationModel
    let activeAlertCount: Int
    /// Time-of-day commute preset to surface at the top of the dashboard, if any.
    var suggestedCommutePreset: RouteCommutePreset?

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
