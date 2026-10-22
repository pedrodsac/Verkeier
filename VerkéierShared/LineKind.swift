import Foundation

/// The kind of vehicle serving a line, as identified by the source feed.
///
/// Shared with the widget extension so presentation never has to guess the
/// mode from a line label: a leading "T" does not make a tram.
nonisolated enum LineKind: String, Codable, Hashable, Sendable {
    case tram
    case train
    case bus
}
