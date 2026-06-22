import Foundation

/// A point-in-time overview of whether the app's data sources are ready.
///
/// Surfaced in settings / debug UI to explain at a glance whether the GTFS
/// feed, ATP access, and other sources are available and current.
struct DataReadinessSnapshot: Sendable {
    /// Headline summarizing overall readiness.
    let summaryTitle: String
    /// Longer explanation accompanying ``summaryTitle``.
    let summaryMessage: String
    /// Per-source readiness rows.
    let items: [DataReadinessItem]
}

/// One source's entry within a ``DataReadinessSnapshot``.
struct DataReadinessItem: Identifiable, Sendable {
    /// Stable identifier for the row.
    let id: String
    /// Source name, e.g. `"GTFS feed"`.
    let title: String
    /// Short status label, e.g. `"Ready"` or `"Stale"`.
    let status: String
    /// Detailed explanation of the status.
    let detail: String
    /// SF Symbol name for the row's icon.
    let iconName: String
}
