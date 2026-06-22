import Foundation

/// A single upcoming departure on a stop's board.
///
/// A departure carries both the scheduled time and, when available, the
/// realtime estimate so the UI can show live delays. Derive the user-facing
/// state with ``status`` rather than inspecting the raw fields.
struct Departure: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier for the departure entry.
    let id: String
    /// Identifier of the stop this departure leaves from.
    let stopId: String
    /// Identifier of the route, when known.
    let routeId: String?
    /// Public line label, e.g. `"16"` or `"T1"`.
    let lineName: String
    /// Headsign / direction shown to the rider.
    let destination: String
    /// Planned departure time from the timetable.
    let scheduledDeparture: Date?
    /// Realtime predicted departure time, if a live feed provided one.
    let realtimeDeparture: Date?
    /// Delay relative to schedule, in whole minutes; `nil` when no realtime
    /// information is available.
    let delayMinutes: Int?
    /// Platform or quay label, when published.
    let platform: String?
    /// Operating company name, when published.
    let operatorName: String?
    /// `true` when the trip has been cancelled.
    let isCancelled: Bool
    /// `true` when realtime data is expected but its status could not be
    /// determined.
    let isStatusUnknown: Bool
    /// Which feed this departure was derived from.
    let dataSource: DataSource
    /// When the realtime data was last refreshed.
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

    /// The rider-facing status, resolved from cancellation, realtime presence,
    /// and ``delayMinutes``.
    ///
    /// Resolution order: cancelled → unknown → (no realtime) scheduled →
    /// delayed when late → on time.
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

/// The displayable state of a ``Departure``.
enum DepartureStatus: Codable, Equatable, Hashable, Sendable {
    /// No realtime data; only the timetable is known.
    case scheduled
    /// Running on time per realtime data.
    case onTime
    /// Running late by the associated number of minutes.
    case delayed(minutes: Int)
    /// The trip has been cancelled.
    case cancelled
    /// Realtime status could not be determined.
    case unknown

    /// Short label suitable for display, e.g. `"On time"` or `"+3 min"`.
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
