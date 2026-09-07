import Foundation

/// One travel direction of a line (e.g. inbound vs. outbound).
nonisolated struct LineDetailDirection: Hashable, Identifiable, Sendable {
    /// Stable identifier for the direction.
    let id: String
    /// Direction title, typically the terminus name.
    let title: String
    /// Optional secondary description.
    let subtitle: String?
}

/// A single stop in a line's ordered stop sequence.
nonisolated struct LineStopSequenceEntry: Hashable, Identifiable, Sendable {
    /// Stable identifier for the entry.
    let id: String
    /// Stop name.
    let name: String
    /// Boarding platform, when published.
    let platform: String?
    /// Stop location, used to draw the sequence on the map.
    let location: LocationPoint
}

/// An upcoming timetabled departure shown on a line's detail screen.
nonisolated struct LineTimetableEntry: Hashable, Identifiable, Sendable {
    /// Stable identifier for the entry.
    let id: String
    /// Scheduled departure time.
    let departureTime: Date
    /// Name of the trip's origin.
    let originName: String
    /// Name of the trip's destination.
    let destinationName: String
}

/// Everything the line-detail screen needs about a single ``TransitRoute``.
///
/// Holds the route, directions, schedule rows, and optional map overlay used by
/// the line-detail presentation.
nonisolated struct LineDetail: Hashable, Sendable {
    /// The route this detail describes.
    let route: TransitRoute
    /// Available travel directions.
    let directions: [LineDetailDirection]
    /// Identifier of the currently shown direction within ``directions``.
    let selectedDirectionID: String
    /// Ordered stops for the selected direction.
    let stopSequence: [LineStopSequenceEntry]
    /// Next departures for the selected direction.
    let upcomingDepartures: [LineTimetableEntry]
    /// One-line summary of the service (e.g. frequency / operating window).
    let serviceSummary: String
    /// Map geometry for the selected direction, if available.
    let mapOverlay: RouteMapOverlay?
}
