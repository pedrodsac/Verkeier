import Foundation
import Testing
import UserNotifications
@testable import LuxTransit

@MainActor
struct FavouritesPersonalizationTests {

    // MARK: Recent stops

    @Test func recordRecentStopDeduplicatesMovesToFrontAndSkipsMock() {
        let store = freshStore()

        #expect(store.recordRecentStop(makeStop(id: "a")).map(\.id) == ["a"])
        #expect(store.recordRecentStop(makeStop(id: "b")).map(\.id) == ["b", "a"])
        // Re-recording an existing stop moves it to the front without duplicating.
        #expect(store.recordRecentStop(makeStop(id: "a")).map(\.id) == ["a", "b"])
        // Mock stops are never recorded.
        #expect(store.recordRecentStop(makeStop(id: "m", dataSource: .mock)).map(\.id) == ["a", "b"])
    }

    @Test func recordRecentStopHonoursLimit() {
        let store = freshStore()
        for index in 0 ..< 10 {
            _ = store.recordRecentStop(makeStop(id: "stop-\(index)"), limit: 8)
        }
        let recents = store.recentStops()
        #expect(recents.count == 8)
        #expect(recents.first?.id == "stop-9")
        #expect(!recents.contains { $0.id == "stop-0" })
    }

    // MARK: Time-of-day commute suggestion

    @Test func suggestsHomeToWorkInTheMorning() {
        let viewModel = TransitMapViewModel(now: { date(hour: 8, minute: 0) })
        viewModel.commutePresets = [preset("Home → Work"), preset("Work → Home")]
        #expect(viewModel.suggestedCommutePreset?.title == "Home → Work")
    }

    @Test func suggestsWorkToHomeInTheEvening() {
        let viewModel = TransitMapViewModel(now: { date(hour: 18, minute: 0) })
        viewModel.commutePresets = [preset("Home → Work"), preset("Work → Home")]
        #expect(viewModel.suggestedCommutePreset?.title == "Work → Home")
    }

    @Test func suggestsNothingMidday() {
        let viewModel = TransitMapViewModel(now: { date(hour: 13, minute: 0) })
        viewModel.commutePresets = [preset("Home → Work"), preset("Work → Home")]
        #expect(viewModel.suggestedCommutePreset == nil)
    }

    // MARK: Disruption alerts

    @Test func disruptionAlertNotifiesOnceForNewFavouriteLineAlert() async {
        let center = NotificationCenterSpy()
        let service = DisruptionAlertService(notificationCenter: center)

        await service.checkAlerts([alert(id: "x", routeIds: ["R1"])], favouriteRouteIds: ["R1"])
        #expect(center.addedRequests.map(\.identifier) == ["disruption.x"])

        // The same alert on a later refresh is already known: no second notification.
        await service.checkAlerts([alert(id: "x", routeIds: ["R1"])], favouriteRouteIds: ["R1"])
        #expect(center.addedRequests.count == 1)
    }

    @Test func disruptionAlertIgnoresAlertsOutsideFavouriteLines() async {
        let center = NotificationCenterSpy()
        let service = DisruptionAlertService(notificationCenter: center)

        await service.checkAlerts([alert(id: "y", routeIds: ["R9"])], favouriteRouteIds: ["R1"])
        #expect(center.addedRequests.isEmpty)
    }

    // MARK: Helpers

    private func freshStore() -> RoutePlannerStore {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return RoutePlannerStore(defaults: defaults)
    }

    private func makeStop(id: String, dataSource: DataSource = .gtfs) -> Stop {
        Stop(
            id: id,
            name: "Stop \(id)",
            location: LocationPoint(latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: dataSource
        )
    }

    private func preset(_ title: String) -> RouteCommutePreset {
        RouteCommutePreset(
            title: title,
            origin: nil,
            destination: RoutePlace(
                title: title,
                location: LocationPoint(latitude: 49.6, longitude: 6.1),
                source: .preset
            )
        )
    }

    private nonisolated func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private func alert(id: String, routeIds: [String]) -> AlertMessage {
        AlertMessage(
            id: id,
            title: "Disruption \(id)",
            body: "Body",
            severity: .warning,
            affectedStopIds: [],
            affectedRouteIds: routeIds,
            startsAt: nil,
            endsAt: nil,
            dataSource: .avl
        )
    }
}

private final class NotificationCenterSpy: DepartureReminderNotificationCenter, @unchecked Sendable {
    var addedRequests: [UNNotificationRequest] = []

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers _: [String]) {}
}
