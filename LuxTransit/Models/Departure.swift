import Foundation

struct Departure: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let stopId: String
    let routeId: String?
    let lineName: String
    let destination: String
    let scheduledDeparture: Date?
    let realtimeDeparture: Date?
    let delayMinutes: Int?
    let platform: String?
    let operatorName: String?
    let isCancelled: Bool
    let isStatusUnknown: Bool
    let dataSource: DataSource
    let lastUpdated: Date?

    nonisolated init(
        id: String,
        stopId: String,
        routeId: String? = nil,
        lineName: String,
        destination: String,
        scheduledDeparture: Date?,
        realtimeDeparture: Date? = nil,
        delayMinutes: Int? = nil,
        platform: String? = nil,
        operatorName: String? = nil,
        isCancelled: Bool = false,
        isStatusUnknown: Bool = false,
        dataSource: DataSource,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.stopId = stopId
        self.routeId = routeId
        self.lineName = lineName
        self.destination = destination
        self.scheduledDeparture = scheduledDeparture
        self.realtimeDeparture = realtimeDeparture
        self.delayMinutes = delayMinutes
        self.platform = platform
        self.operatorName = operatorName
        self.isCancelled = isCancelled
        self.isStatusUnknown = isStatusUnknown
        self.dataSource = dataSource
        self.lastUpdated = lastUpdated
    }

    var status: DepartureStatus {
        if isCancelled {
            return .cancelled
        }

        if isStatusUnknown {
            return .unknown
        }

        guard realtimeDeparture != nil || delayMinutes != nil else {
            return .scheduled
        }

        guard let delayMinutes else {
            return .unknown
        }

        if delayMinutes > 0 {
            return .delayed(minutes: delayMinutes)
        }

        return .onTime
    }
}

enum DepartureStatus: Codable, Equatable, Hashable, Sendable {
    case scheduled
    case onTime
    case delayed(minutes: Int)
    case cancelled
    case unknown

    var displayText: String {
        switch self {
        case .scheduled: "Scheduled"
        case .onTime: "On time"
        case .delayed(let minutes): "+\(minutes) min"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}
