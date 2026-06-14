import ActivityKit
import Foundation

nonisolated struct DepartureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let scheduledDeparture: Date?
        let realtimeDeparture: Date?
        let delayMinutes: Int?
        let isCancelled: Bool
        let lastUpdated: Date
        let staleAfter: Date

        var statusText: String {
            if isCancelled {
                return "Cancelled"
            }

            guard realtimeDeparture != nil || delayMinutes != nil else {
                return "Scheduled"
            }

            guard let delayMinutes else {
                return "Unknown"
            }

            return delayMinutes > 0 ? "+\(delayMinutes) min" : "On time"
        }

        var displayDepartureDate: Date? {
            realtimeDeparture ?? scheduledDeparture
        }
    }

    let departureId: String
    let stopId: String
    let stopName: String
    let lineName: String
    let destination: String
    let platform: String?
}
