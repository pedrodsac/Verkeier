import Foundation
import Observation
import UserNotifications

/// Fires a local notification when a newly observed AVL disruption affects a line
/// serving one of the rider's favourite stops.
///
/// `knownAlertIds` is in-memory only and resets on each launch: riders are
/// notified for disruptions that appear while the app is open, not for ones that
/// were already active before launch (which would be noise on every cold start).
@Observable
@MainActor
final class DisruptionAlertService {
    private var knownAlertIds: Set<String> = []
    private let notificationCenter: any DepartureReminderNotificationCenter

    init(
        notificationCenter: any DepartureReminderNotificationCenter = UNUserNotificationCenter.current()
    ) {
        self.notificationCenter = notificationCenter
    }

    /// Call after each AVL refresh with the current alert list and the routes
    /// served by all favourite stops. Fires a local notification for each alert
    /// that is new since the last call and affects a favourite line.
    func checkAlerts(
        _ alerts: [AlertMessage],
        favouriteRouteIds: Set<String>
    ) async {
        let relevant = alerts.filter { alert in
            !knownAlertIds.contains(alert.id)
                && !alert.affectedRouteIds.isEmpty
                && !Set(alert.affectedRouteIds).isDisjoint(with: favouriteRouteIds)
        }
        knownAlertIds.formUnion(alerts.map(\.id))

        for alert in relevant {
            try? await sendDisruptionNotification(for: alert)
        }
    }

    private func sendDisruptionNotification(for alert: AlertMessage) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Disruption on a favourite line"
        content.body = alert.title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disruption.\(alert.id)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }
}
