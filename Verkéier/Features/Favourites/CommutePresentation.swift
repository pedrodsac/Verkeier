import Foundation

struct CommuteDashboardViewModel {
    let nearby: NearbyStopsPresentationModel
    let activeAlertCount: Int
    /// Time-of-day commute preset to surface at the top of the dashboard, if any.
    var suggestedCommutePreset: RouteCommutePreset?
    let specialEvents: [SpecialEvent]
}
