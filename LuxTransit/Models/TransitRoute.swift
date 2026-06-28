import Foundation

/// A transit line / route, such as a single bus or tram line.
struct TransitRoute: Codable, Hashable, Identifiable {
    /// Stable route identifier (GTFS `route_id` where applicable).
    let id: String
    /// Short public label, e.g. `"16"` or `"T1"`.
    let shortName: String
    /// Optional descriptive name, e.g. the line's terminus-to-terminus title.
    let longName: String?
    /// The mode this route operates in.
    let mode: TransportMode
    /// Operating company name, when known.
    let operatorName: String?
    /// Which feed this route was derived from.
    let dataSource: DataSource

    nonisolated init(
        id: String,
        shortName: String,
        longName: String? = nil,
        mode: TransportMode,
        operatorName: String? = nil,
        dataSource: DataSource
    ) {
        self.id = id
        self.shortName = shortName
        self.longName = longName
        self.mode = mode
        self.operatorName = operatorName
        self.dataSource = dataSource
    }
}

extension TransitRoute {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(shortName)
        hasher.combine(longName)
        hasher.combine(mode)
        hasher.combine(operatorName)
        hasher.combine(dataSource)
    }
}
