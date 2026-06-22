import Foundation

/// A service disruption or information message.
///
/// Parsed from the Ville de Luxembourg AVL feed (see ``AVLClient``) and shown in
/// the alerts feature. ``affectedStopIds`` and ``affectedRouteIds`` let the UI
/// cross-reference an alert to the stops and lines a rider is viewing.
struct AlertMessage: Codable, Hashable, Identifiable, Sendable {
    /// How serious the disruption is.
    enum Severity: String, Codable, CaseIterable, Identifiable, Sendable {
        case info
        case warning
        case severe
        /// Severity could not be determined from the source.
        case unknown

        var id: String { rawValue }
    }

    /// Stable identifier for the message.
    let id: String
    /// Short headline.
    let title: String
    /// Full message text.
    let body: String
    /// Severity used for sorting and styling.
    let severity: Severity
    /// Identifiers of stops this alert affects.
    let affectedStopIds: [String]
    /// Identifiers of routes this alert affects.
    let affectedRouteIds: [String]
    /// When the disruption begins, if specified.
    let startsAt: Date?
    /// When the disruption ends, if specified.
    let endsAt: Date?
    /// Which feed this alert was derived from.
    let dataSource: DataSource
}
