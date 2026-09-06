import Foundation

extension RouteSearchContext {
    /// The most specific matching GTFS rule wins. The original alighting stop
    /// survives chained walks, so A→B→C cannot evade an A→C prohibition.
    func transferRule(fromTrip: GTFSTimetableTripEntry, fromStopID: String,
                      toTrip: GTFSTimetableTripEntry, toStopID: String) -> GTFSTimetableTransferEntry? {
        transferRules.filter { rule in
            func matches(_ value: String?, _ actual: String) -> Bool {
                value == nil || value == "" || value == actual
            }
            return (rule.fromStopId.isEmpty || rule.fromStopId == fromStopID)
                && (rule.toStopId.isEmpty || rule.toStopId == toStopID)
                && matches(rule.fromRouteID, fromTrip.routeId) && matches(rule.toRouteID, toTrip.routeId)
                && matches(rule.fromTripID, fromTrip.originalTripID ?? fromTrip.id)
                && matches(rule.toTripID, toTrip.originalTripID ?? toTrip.id)
        }.max { lhs, rhs in
            func specificity(_ rule: GTFSTimetableTransferEntry) -> Int {
                let trips = [rule.fromTripID, rule.toTripID].filter { $0?.isEmpty == false }.count
                let routes = [rule.fromRouteID, rule.toRouteID].filter { $0?.isEmpty == false }.count
                return trips * 4 + routes
            }
            if specificity(lhs) != specificity(rhs) { return specificity(lhs) < specificity(rhs) }
            // Malformed, equally specific rules: prefer a prohibition, then the longer minimum.
            if lhs.transferType == 3 || rhs.transferType == 3 { return rhs.transferType == 3 && lhs.transferType != 3 }
            return (lhs.minimumTransferSeconds ?? 0) < (rhs.minimumTransferSeconds ?? 0)
        }
    }
}
