import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
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

    /// After an AVL refresh, notify the rider about any new disruption that
    /// affects a line serving one of their favourite stops. Resolves the favourite
    /// stops' route ids with bounded fan-out, then defers to
    /// ``DisruptionAlertService`` to dedupe and deliver.
    func checkDisruptionAlerts(
        disruptionAlertService: DisruptionAlertService,
        favouriteStops _: [Stop]
    ) async {
        guard !alerts.isEmpty else { return }
        await disruptionAlertService.checkAlerts(alerts, favouriteRouteIds: [])
    }

    func loadLineDetail(using gtfsService: any GTFSService, now: Date = .now) async {
        guard let route = selectedLineDetailRoute else {
            selectedLineDetail = nil
            selectedLineDetailErrorMessage = "Choose a line to view its timetable."
            return
        }

        selectedLineDetailErrorMessage = nil
        selectedLineDetail = await gtfsService.lineDetail(
            for: route,
            directionID: selectedLineDetailDirectionID,
            at: now
        )
        if selectedLineDetail == nil {
            selectedLineDetailErrorMessage = "No active timetable data is available for this line."
        }
    }

    var areAlertsStale: Bool {
        guard let alertsLastUpdated else { return false }
        return Date().timeIntervalSince(alertsLastUpdated) > 300
    }

    var activeAlertCount: Int {
        alerts.count
    }

    var stopDetailAlerts: [AlertMessage] {
        guard let selectedStop else { return [] }
        let routeIDs = Set(selectedStopRoutes.map(\.id))
        return alerts.filter { alert in
            alert.affectedStopIds.contains(selectedStop.id)
                || !routeIDs.isDisjoint(with: alert.affectedRouteIds)
        }
    }

    var routeAlerts: [AlertMessage] {
        guard let selectedRouteOption else { return [] }
        let routeIDs = Set(selectedRouteOption.plan.legs.compactMap(\.routeId))
        let stopIDs = Set(selectedRouteOption.plan.legs.flatMap { leg in
            [leg.originStopId, leg.destinationStopId].compactMap(\.self)
        })
        return alerts.filter { alert in
            !routeIDs.isDisjoint(with: alert.affectedRouteIds)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }

    /// Active alerts that affect each transit leg of the selected route plan,
    /// keyed by leg index (as a string). Walking legs are skipped.
    var routeLegAlerts: [String: [AlertMessage]] {
        guard let plan = selectedRouteOption?.plan else { return [:] }
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

    var lineDetailAlerts: [AlertMessage] {
        guard let route = selectedLineDetailRoute else { return [] }
        let stopIDs = Set(selectedLineDetail?.stopSequence.map(\.id) ?? [])
        return alerts.filter { alert in
            alert.affectedRouteIds.contains(route.id)
                || !stopIDs.isDisjoint(with: alert.affectedStopIds)
        }
    }
}
