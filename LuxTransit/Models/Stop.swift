import Foundation

/// Wheelchair boarding accessibility for a stop, from GTFS `wheelchair_boarding`.
nonisolated enum WheelchairAccess: String, Codable, Hashable {
    case unknown
    case accessible
    case notAccessible

    /// Maps a raw GTFS `wheelchair_boarding` value ("0"/"1"/"2") to a case.
    nonisolated init(gtfsValue: String?) {
        switch gtfsValue?.trimmingCharacters(in: .whitespaces) {
        case "1": self = .accessible
        case "2": self = .notAccessible
        default: self = .unknown
        }
    }
}

/// A public-transport stop or station.
///
/// `Stop` is the canonical place model used across search, the map, departure
/// boards, and route planning. Instances originate from the on-device GTFS
/// index (``DataSource/gtfs``) or the ATP nearby-stops feed
/// (``DataSource/atpOpenAPI``) and are mapped into this value type before they
/// reach any view.
struct Stop: Codable, Hashable, Identifiable {
    /// Stable identifier for the stop, used for `Identifiable` and as the
    /// lookup key in GTFS and ATP requests.
    let id: String
    /// Human-readable stop name, e.g. `"Luxembourg, Gare Centrale"`.
    let name: String
    /// Optional town or district the stop belongs to.
    let locality: String?
    /// Geographic position of the stop.
    let location: LocationPoint
    /// Transport modes that serve this stop (bus, tram, train, …).
    let modes: [TransportMode]
    /// Which feed this stop was derived from.
    let dataSource: DataSource
    /// Per-platform identifiers grouped under this stop.
    ///
    /// A logical stop may aggregate several physical platforms, each of which
    /// has its own ATP departure board. Defaults to `[id]` when no distinct
    /// platforms are known.
    let platformIds: [String]
    /// Wheelchair boarding accessibility, from GTFS `wheelchair_boarding`.
    let wheelchairBoarding: WheelchairAccess

    /// Creates a stop.
    ///
    /// - Parameter platformIds: Distinct platform identifiers. Blank entries are
    ///   trimmed and duplicates removed; if the result is empty the stop's own
    ///   `id` is used as the single platform.
    nonisolated init(
        id: String,
        name: String,
        locality: String? = nil,
        location: LocationPoint,
        modes: [TransportMode] = [],
        dataSource: DataSource,
        platformIds: [String]? = nil,
        wheelchairBoarding: WheelchairAccess = .unknown
    ) {
        self.id = id
        self.name = name
        self.locality = locality
        self.location = location
        self.modes = modes
        self.dataSource = dataSource
        self.platformIds = Self.normalizedPlatformIds(platformIds, fallbackId: id)
        self.wheelchairBoarding = wheelchairBoarding
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case locality
        case location
        case modes
        case dataSource
        case platformIds
        case wheelchairBoarding
    }

    /// Decodes a stop, applying the same platform normalization as the
    /// memberwise initializer so persisted and freshly built stops behave
    /// identically.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)

        self.id = id
        name = try container.decode(String.self, forKey: .name)
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        location = try container.decode(LocationPoint.self, forKey: .location)
        modes = try container.decode([TransportMode].self, forKey: .modes)
        dataSource = try container.decode(DataSource.self, forKey: .dataSource)
        platformIds = try Self.normalizedPlatformIds(
            container.decodeIfPresent([String].self, forKey: .platformIds),
            fallbackId: id
        )
        wheelchairBoarding = try container.decodeIfPresent(
            WheelchairAccess.self, forKey: .wheelchairBoarding
        ) ?? .unknown
    }

    private nonisolated static func normalizedPlatformIds(_ ids: [String]?, fallbackId: String) -> [String] {
        let normalized = (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? [fallbackId] : Array(dictOrderedSet: normalized)
    }
}

private extension [String] {
    nonisolated init(dictOrderedSet values: [String]) {
        var seen: Set<String> = []
        self = values.filter { seen.insert($0).inserted }
    }
}
