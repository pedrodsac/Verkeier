import Foundation
import Testing
import UserNotifications

@testable import LuxTransit

@MainActor
struct DepartureReminderServiceTests {
    @Test func schedulingReminderPersistsStateAndCreatesLeaveNotification() async throws {
        clearSharedReminderStorage()
        defer { clearSharedReminderStorage() }
        let center = NotificationCenterSpy()
        let service = DepartureReminderService(
            notificationCenter: center,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let stop = makeStop()
        let departure = makeDeparture(
            scheduledDeparture: Date(timeIntervalSince1970: 1_600),
            realtimeDeparture: Date(timeIntervalSince1970: 1_660)
        )

        await service.scheduleReminder(for: departure, stop: stop, leadTimeMinutes: 5)

        let reminder = try #require(service.activeReminder)
        #expect(reminder.departureId == departure.id)
        #expect(reminder.leadTimeMinutes == 5)
        #expect(center.requestAuthorizationCallCount == 1)
        #expect(center.addedRequests.map(\.identifier) == ["departure-reminder.leave.dep-1"])
    }

    @Test func syncTrackedDepartureSendsDelayNotificationOncePerDelayValue() async throws {
        clearSharedReminderStorage()
        defer { clearSharedReminderStorage() }
        let center = NotificationCenterSpy()
        let service = DepartureReminderService(
            notificationCenter: center,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let stop = makeStop()
        let scheduledDeparture = Date(timeIntervalSince1970: 1_600)

        await service.scheduleReminder(
            for: makeDeparture(
                scheduledDeparture: scheduledDeparture,
                realtimeDeparture: scheduledDeparture,
                delayMinutes: 0
            ),
            stop: stop,
            leadTimeMinutes: 5
        )
        center.addedRequests.removeAll()

        await service.syncTrackedDeparture(
            makeDeparture(
                scheduledDeparture: scheduledDeparture,
                realtimeDeparture: scheduledDeparture.addingTimeInterval(300),
                delayMinutes: 5
            ),
            stopName: stop.name
        )

        #expect(center.addedRequests.map(\.identifier).contains("departure-reminder.delayed.dep-1"))
        #expect(service.activeReminder?.notifiedDelayMinutes == 5)

        center.addedRequests.removeAll()
        await service.syncTrackedDeparture(
            makeDeparture(
                scheduledDeparture: scheduledDeparture,
                realtimeDeparture: scheduledDeparture.addingTimeInterval(300),
                delayMinutes: 5
            ),
            stopName: stop.name
        )

        #expect(center.addedRequests.map(\.identifier) == ["departure-reminder.leave.dep-1"])
    }

    @Test func syncTrackedDepartureSendsCancellationAndCancelsPendingLeaveAlert() async throws {
        clearSharedReminderStorage()
        defer { clearSharedReminderStorage() }
        let center = NotificationCenterSpy()
        let service = DepartureReminderService(
            notificationCenter: center,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let stop = makeStop()

        await service.scheduleReminder(
            for: makeDeparture(
                scheduledDeparture: Date(timeIntervalSince1970: 1_600),
                realtimeDeparture: Date(timeIntervalSince1970: 1_600)
            ),
            stop: stop,
            leadTimeMinutes: 10
        )
        center.addedRequests.removeAll()
        center.removedIdentifiers.removeAll()

        await service.syncTrackedDeparture(
            makeDeparture(
                scheduledDeparture: Date(timeIntervalSince1970: 1_600),
                realtimeDeparture: Date(timeIntervalSince1970: 1_600),
                delayMinutes: 0,
                isCancelled: true
            ),
            stopName: stop.name
        )

        #expect(center.addedRequests.map(\.identifier).contains("departure-reminder.cancelled.dep-1"))
        #expect(center.removedIdentifiers.contains("departure-reminder.leave.dep-1"))
        #expect(service.activeReminder?.didNotifyCancellation == true)
    }

    private func makeStop() -> Stop {
        Stop(
            id: "stop-1",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(name: "Hamilius", latitude: 49.6116, longitude: 6.1319),
            modes: [.bus],
            dataSource: .gtfs
        )
    }

    private func makeDeparture(
        scheduledDeparture: Date?,
        realtimeDeparture: Date?,
        delayMinutes: Int? = nil,
        isCancelled: Bool = false
    ) -> Departure {
        Departure(
            id: "dep-1",
            stopId: "stop-1",
            lineName: "16",
            destination: "Kirchberg",
            scheduledDeparture: scheduledDeparture,
            realtimeDeparture: realtimeDeparture,
            delayMinutes: delayMinutes,
            isCancelled: isCancelled,
            dataSource: .atpOpenAPI,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func clearSharedReminderStorage() {
        SharedTransitDataStore.userDefaults.removeObject(
            forKey: SharedTransitDataStore.trackedDepartureReminderKey)
        UserDefaults.standard.removeObject(forKey: SharedTransitDataStore.trackedDepartureReminderKey)
    }
}

private final class NotificationCenterSpy: DepartureReminderNotificationCenter, @unchecked Sendable {
    var requestAuthorizationCallCount = 0
    var requestAuthorizationResult = true
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}
