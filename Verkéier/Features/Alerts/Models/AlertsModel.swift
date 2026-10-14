import Foundation
import Observation

/// Service alerts from the AVL feed, and the subsets that affect a stop, a
/// route, or a line.
@MainActor @Observable
final class AlertsModel {
    var alerts: [AlertMessage] = []
    var isLoadingAlerts = false
    var alertsErrorMessage: String?
    var alertsLastUpdated: Date?

    var areAlertsStale: Bool {
        guard let alertsLastUpdated else { return false }
        return Date().timeIntervalSince(alertsLastUpdated) > 300
    }

    var activeAlertCount: Int {
        alerts.count
    }

    func loadAlerts(using avlClient: any AVLClient) async {
        isLoadingAlerts = true
        alertsErrorMessage = nil

        do {
            alerts = try await avlClient.fetchMessages()
            alertsLastUpdated = .now
        } catch {
            alerts = []
            alertsErrorMessage = "AVL alerts could not be loaded."
        }

        isLoadingAlerts = false
    }

    /// Reloads the alerts, then notifies the rider about any new disruption.
    func refresh(using avlClient: any AVLClient, disruptionAlertService: DisruptionAlertService) async {
        await loadAlerts(using: avlClient)
        await checkDisruptionAlerts(disruptionAlertService: disruptionAlertService)
    }

    /// After an AVL refresh, notify the rider about any new disruption.
    /// ``DisruptionAlertService`` dedupes and delivers.
    func checkDisruptionAlerts(disruptionAlertService: DisruptionAlertService) async {
        guard !alerts.isEmpty else { return }
        await disruptionAlertService.checkAlerts(alerts, favouriteRouteIds: [])
    }
}

// MARK: - Affected subsets

extension AlertsModel {
    func alerts(forStop stop: Stop?, routes: [TransitRoute]) -> [AlertMessage] {
        guard let stop else { return [] }
        let routeIDs = Set(routes.map(\.id))
        return alerts.filter { alert in
            alert.affectedStopIds.contains(stop.id)
                || !routeIDs.isDisjoint(with: alert.affectedRouteIds)
        }
    }

    func alerts(forRoute option: RouteOption?) -> [AlertMessage] {
        guard let option else { return [] }
        let routeIDs = Set(option.plan.legs.compactMap(\.routeId))
        let stopIDs = Set(
            option.plan.legs.flatMap { leg in
                [leg.originStopId, leg.destinationStopId].compactMap(\.self)
            }
        )
        return alerts.filter { alert in
            !routeIDs.isDisjoint(with: alert.affectedRouteIds)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }

    /// Active alerts that affect each transit leg of `option`, keyed by leg
    /// index (as a string). Walking legs are skipped.
    func legAlerts(forRoute option: RouteOption?) -> [String: [AlertMessage]] {
        guard let plan = option?.plan else { return [:] }
        var result: [String: [AlertMessage]] = [:]
        for (index, leg) in plan.legs.enumerated() where leg.transportKind == .transit {
            let legStopIDs = Set([leg.originStopId, leg.destinationStopId].compactMap(\.self))
            let matching = alerts.filter { alert in
                if let routeID = leg.routeId, alert.affectedRouteIds.contains(routeID) {
                    return true
                }
                return !legStopIDs.isDisjoint(with: alert.affectedStopIds)
            }
            if !matching.isEmpty { result[String(index)] = matching }
        }
        return result
    }

    func alerts(forLine route: TransitRoute?, detail: LineDetail?) -> [AlertMessage] {
        guard let route else { return [] }
        let stopIDs = Set(detail?.stopSequence.map(\.id) ?? [])
        return alerts.filter { alert in
            alert.affectedRouteIds.contains(route.id)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }
}
