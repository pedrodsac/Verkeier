import Foundation
import Observation
import UserNotifications

protocol DepartureReminderNotificationCenter: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: DepartureReminderNotificationCenter {
}

@Observable
@MainActor
final class DepartureReminderService {
    private let notificationCenter: any DepartureReminderNotificationCenter
    private let now: @Sendable () -> Date

    private(set) var activeReminder: SharedTrackedDepartureReminder?
    var lastErrorMessage: String?

    init(
        notificationCenter: any DepartureReminderNotificationCenter = UNUserNotificationCenter.current(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        activeReminder = SharedTransitDataStore.trackedReminder()
    }

    func scheduleReminder(for departure: Departure, stop: Stop, leadTimeMinutes: Int) async {
        let departureDate = departure.realtimeDeparture ?? departure.scheduledDeparture
        guard let departureDate else {
            lastErrorMessage = "This departure does not have a reminder time yet."
            return
        }

        guard departureDate > now() else {
            lastErrorMessage = "This departure has already left."
            return
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            guard granted else {
                lastErrorMessage = "Notifications are disabled for LuxTransit."
                return
            }

            let reminder = SharedTrackedDepartureReminder(
                departureId: departure.id,
                stopId: stop.id,
                stopName: stop.name,
                lineName: departure.lineName,
                destination: departure.destination,
                scheduledDeparture: departure.scheduledDeparture,
                realtimeDeparture: departure.realtimeDeparture,
                delayMinutes: departure.delayMinutes,
                isCancelled: departure.isCancelled,
                leadTimeMinutes: leadTimeMinutes,
                lastUpdated: departure.lastUpdated ?? now()
            )

            try await scheduleLeaveNotification(for: reminder)
            persist(reminder)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Departure reminder could not be scheduled."
        }
    }

    func cancelReminder() {
        guard let activeReminder else { return }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: pendingIdentifiers(for: activeReminder.departureId)
        )
        persist(nil)
        lastErrorMessage = nil
    }

    func syncTrackedDeparture(_ departure: Departure, stopName: String? = nil) async {
        guard let activeReminder, activeReminder.departureId == departure.id else { return }

        var updatedReminder = SharedTrackedDepartureReminder(
            departureId: departure.id,
            stopId: activeReminder.stopId,
            stopName: stopName ?? activeReminder.stopName,
            lineName: departure.lineName,
            destination: departure.destination,
            scheduledDeparture: departure.scheduledDeparture,
            realtimeDeparture: departure.realtimeDeparture,
            delayMinutes: departure.delayMinutes,
            isCancelled: departure.isCancelled,
            leadTimeMinutes: activeReminder.leadTimeMinutes,
            notifiedDelayMinutes: activeReminder.notifiedDelayMinutes,
            didNotifyCancellation: activeReminder.didNotifyCancellation,
            lastUpdated: departure.lastUpdated ?? now()
        )

        do {
            if departure.isCancelled, !activeReminder.didNotifyCancellation {
                try await sendStatusNotification(
                    id: cancelledIdentifier(for: departure.id),
                    title: "Departure cancelled",
                    body: "\(departure.lineName) to \(departure.destination) from \(updatedReminder.stopName) has been cancelled."
                )
                updatedReminder = SharedTrackedDepartureReminder(
                    departureId: updatedReminder.departureId,
                    stopId: updatedReminder.stopId,
                    stopName: updatedReminder.stopName,
                    lineName: updatedReminder.lineName,
                    destination: updatedReminder.destination,
                    scheduledDeparture: updatedReminder.scheduledDeparture,
                    realtimeDeparture: updatedReminder.realtimeDeparture,
                    delayMinutes: updatedReminder.delayMinutes,
                    isCancelled: updatedReminder.isCancelled,
                    leadTimeMinutes: updatedReminder.leadTimeMinutes,
                    notifiedDelayMinutes: updatedReminder.notifiedDelayMinutes,
                    didNotifyCancellation: true,
                    lastUpdated: updatedReminder.lastUpdated
                )
                notificationCenter.removePendingNotificationRequests(
                    withIdentifiers: [leaveIdentifier(for: departure.id)]
                )
            } else if let delayMinutes = departure.delayMinutes,
                delayMinutes > 0,
                activeReminder.notifiedDelayMinutes != delayMinutes
            {
                try await sendStatusNotification(
                    id: delayedIdentifier(for: departure.id),
                    title: "Departure delayed",
                    body: "\(departure.lineName) to \(departure.destination) is now \(delayMinutes) min late."
                )
                updatedReminder = SharedTrackedDepartureReminder(
                    departureId: updatedReminder.departureId,
                    stopId: updatedReminder.stopId,
                    stopName: updatedReminder.stopName,
                    lineName: updatedReminder.lineName,
                    destination: updatedReminder.destination,
                    scheduledDeparture: updatedReminder.scheduledDeparture,
                    realtimeDeparture: updatedReminder.realtimeDeparture,
                    delayMinutes: updatedReminder.delayMinutes,
                    isCancelled: updatedReminder.isCancelled,
                    leadTimeMinutes: updatedReminder.leadTimeMinutes,
                    notifiedDelayMinutes: delayMinutes,
                    didNotifyCancellation: updatedReminder.didNotifyCancellation,
                    lastUpdated: updatedReminder.lastUpdated
                )
            }

            if !updatedReminder.didNotifyCancellation {
                try await scheduleLeaveNotification(for: updatedReminder)
            }

            persist(updatedReminder)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Departure reminder updates could not be delivered."
        }
    }

    private func scheduleLeaveNotification(for reminder: SharedTrackedDepartureReminder) async throws {
        guard let departureDate = reminder.realtimeDeparture ?? reminder.scheduledDeparture else { return }

        let triggerDate = departureDate.addingTimeInterval(TimeInterval(-reminder.leadTimeMinutes * 60))
        let title = "Leave in \(reminder.leadTimeMinutes) min"
        let body = "\(reminder.lineName) to \(reminder.destination) leaves from \(reminder.stopName) at \(departureDate.formatted(date: .omitted, time: .shortened))."

        if triggerDate <= now() {
            try await sendStatusNotification(
                id: leaveIdentifier(for: reminder.departureId),
                title: title,
                body: body
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: leaveIdentifier(for: reminder.departureId),
            content: content,
            trigger: trigger
        )

        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [leaveIdentifier(for: reminder.departureId)]
        )
        try await notificationCenter.add(request)
    }

    private func sendStatusNotification(id: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    private func persist(_ reminder: SharedTrackedDepartureReminder?) {
        activeReminder = reminder
        SharedTransitDataStore.saveTrackedReminder(reminder)
    }

    private func pendingIdentifiers(for departureId: String) -> [String] {
        [
            leaveIdentifier(for: departureId),
            delayedIdentifier(for: departureId),
            cancelledIdentifier(for: departureId),
        ]
    }

    private func leaveIdentifier(for departureId: String) -> String {
        "departure-reminder.leave.\(departureId)"
    }

    private func delayedIdentifier(for departureId: String) -> String {
        "departure-reminder.delayed.\(departureId)"
    }

    private func cancelledIdentifier(for departureId: String) -> String {
        "departure-reminder.cancelled.\(departureId)"
    }
}
