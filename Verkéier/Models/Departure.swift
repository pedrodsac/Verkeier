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
    /// The previously published platform when ATP signals a platform change;
    /// `nil` when the platform is unchanged or no change signal is available.
    // ponytail: stubbed — populate from ATP when the platform-change signal is confirmed.
    let previousPlatform: String?
    /// ATP's stable journey reference, when supplied. This survives board
    /// reordering and should be used for tracking and reminders.
    let journeyReference: String?
    /// Service-status text and rider-facing notes supplied by ATP.
    let serviceNote: String?
    /// Set when the vehicle continues past the listed terminus (through service),
    /// naming where it carries on to; `nil` when not a through service.
    // ponytail: stubbed — populate from GTFS block / ATP when continuation data is confirmed.
    let continuesAs: String?
    /// Crowding level when the feed provides it; `nil` when unknown.
    // ponytail: stubbed — populate from ATP when the occupancy feed is confirmed.
    let occupancy: OccupancyLevel?

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
        lastUpdated: Date? = nil,
        previousPlatform: String? = nil,
        journeyReference: String? = nil,
        serviceNote: String? = nil,
        continuesAs: String? = nil,
        occupancy: OccupancyLevel? = nil
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
        self.previousPlatform = previousPlatform
        self.journeyReference = journeyReference
        self.serviceNote = serviceNote
        self.continuesAs = continuesAs
        self.occupancy = occupancy
    }

    /// Whether ATP has signalled a platform change for this departure.
    var hasPlatformChange: Bool {
        guard let previousPlatform, let platform else { return false }
        return previousPlatform != platform
    }

    /// Returns a copy with a platform supplied by another trusted feed.
    ///
    /// Live and timetable feeds can describe the same departure with
    /// different completeness. Keeping this operation on the value model
    /// lets merge layers enrich only the missing field without dropping any
    /// live status or tracking metadata.
    nonisolated func replacingPlatform(with platform: String) -> Departure {
        Departure(
            id: id,
            stopId: stopId,
            routeId: routeId,
            lineName: lineName,
            destination: destination,
            scheduledDeparture: scheduledDeparture,
            realtimeDeparture: realtimeDeparture,
            delayMinutes: delayMinutes,
            platform: platform,
            operatorName: operatorName,
            isCancelled: isCancelled,
            isStatusUnknown: isStatusUnknown,
            dataSource: dataSource,
            lastUpdated: lastUpdated,
            previousPlatform: previousPlatform,
            journeyReference: journeyReference,
            serviceNote: serviceNote,
            continuesAs: continuesAs,
            occupancy: occupancy
        )
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

/// Crowding level for a departure, surfaced when the feed provides occupancy.
enum OccupancyLevel: String, Codable, Hashable, CaseIterable, Sendable {
    case empty
    case manySeats
    case fewSeats
    case standingRoom
    case full

    /// Short rider-facing label.
    var displayText: String {
        switch self {
        case .empty: "Empty"
        case .manySeats: "Many seats"
        case .fewSeats: "Few seats"
        case .standingRoom: "Standing only"
        case .full: "Full"
        }
    }

    /// SF Symbol communicating crowding at a glance.
    var symbolName: String {
        switch self {
        case .empty, .manySeats: "person.fill"
        case .fewSeats: "person.2.fill"
        case .standingRoom, .full: "person.3.fill"
        }
    }
}

/// The displayable state of a ``Departure``.
enum DepartureStatus: Codable, Equatable, Hashable {
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
        case let .delayed(minutes): "+\(minutes) min"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}
