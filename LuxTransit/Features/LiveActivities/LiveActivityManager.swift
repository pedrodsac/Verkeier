import ActivityKit
import Foundation
import Observation

@Observable
@MainActor
final class LiveActivityManager {
    private var trackedActivity: Activity<DepartureActivityAttributes>?
    var trackedDepartureId: String?
    var lastErrorMessage: String?

    var isTrackingDeparture: Bool {
        trackedActivity != nil
    }

    func startTracking(departure: Departure, stop: Stop) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastErrorMessage = "Live Activities are disabled."
            return
        }

        await endTracking()

        let attributes = DepartureActivityAttributes(
            departureId: departure.id,
            stopId: stop.id,
            stopName: stop.name,
            lineName: departure.lineName,
            destination: departure.destination,
            platform: departure.platform
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState(for: departure), staleDate: departureStaleDate(from: departure)),
                pushType: nil
            )
            trackedActivity = activity
            trackedDepartureId = departure.id
            lastErrorMessage = nil
        } catch {
            trackedActivity = nil
            trackedDepartureId = nil
            lastErrorMessage = "Departure tracking could not be started."
        }
    }

    func updateTracking(departure: Departure) async {
        guard let trackedActivity, departure.id == trackedDepartureId else { return }
        await trackedActivity.update(
            .init(state: contentState(for: departure), staleDate: departureStaleDate(from: departure))
        )
    }

    func endTracking() async {
        guard let trackedActivity else { return }
        await trackedActivity.end(nil, dismissalPolicy: .immediate)
        self.trackedActivity = nil
        trackedDepartureId = nil
    }

    private func contentState(for departure: Departure) -> DepartureActivityAttributes.ContentState {
        let staleAfter = departureStaleDate(from: departure)
        return DepartureActivityAttributes.ContentState(
            scheduledDeparture: departure.scheduledDeparture,
            realtimeDeparture: departure.realtimeDeparture,
            delayMinutes: departure.delayMinutes,
            isCancelled: departure.isCancelled,
            lastUpdated: departure.lastUpdated ?? .now,
            staleAfter: staleAfter
        )
    }

    private func departureStaleDate(from departure: Departure) -> Date {
        let baseDate = departure.lastUpdated ?? .now
        return baseDate.addingTimeInterval(90)
    }
}
