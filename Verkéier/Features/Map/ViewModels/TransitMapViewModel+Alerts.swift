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
        using gtfsService: any GTFSService,
        disruptionAlertService: DisruptionAlertService,
        favouriteStops: [Stop]
    ) async {
        guard !favouriteStops.isEmpty, !alerts.isEmpty else { return }

        let favouriteRouteIds = await Set(
            withTaskGroup(of: [TransitRoute].self) { group in
                for stop in favouriteStops {
                    group.addTask { await gtfsService.routesForStop(id: stop.id) }
                }
                return await group.reduce(into: []) { $0 += $1 }
            }.map(\.id)
        )

        await disruptionAlertService.checkAlerts(alerts, favouriteRouteIds: favouriteRouteIds)
    }

    func loadLineDetail(using gtfsService: any GTFSService, now: Date = .now) async {
        guard let route = selectedLineDetailRoute,
              let timetable = await gtfsService.timetableIndex() else {
            selectedLineDetail = nil
            selectedLineDetailErrorMessage = "Line details are not available yet."
            return
        }

        let service = LineDetailService()
        selectedLineDetail = service.detail(
            for: route,
            selectedStopId: selectedStop?.id,
            timetable: timetable,
            now: now,

            selectedDirectionID: selectedLineDetailDirectionID
        )
        selectedLineDetailErrorMessage =
            selectedLineDetail == nil ? "No GTFS timetable details are available for this line." : nil
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
