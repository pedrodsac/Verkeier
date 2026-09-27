import Foundation

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
    ///
    /// When a feed omits this field but prefixes the stop name with a
    /// locality, the initializer derives it from that prefix.
    let locality: String?

    /// The complete stop name used for search, including its locality when
    /// the feed stores that part separately.
    ///
    /// The UI may present ``displayName`` without the locality because the
    /// locality is shown as a subtitle. Search must continue to use this full
    /// value so a query such as "Arlon" can find "Arlon, Gare".
    nonisolated var fullName: String {
        let cleanedName = name.stationDisplayName
        guard let locality = locality?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locality.isEmpty else {
            return cleanedName
        }

        let trimmedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let localityPrefix = "\(locality),"
        if trimmedName.prefix(localityPrefix.count).caseInsensitiveCompare(localityPrefix) == .orderedSame
            || trimmedName.caseInsensitiveCompare(locality) == .orderedSame {
            return trimmedName
        }

        return "\(locality), \(trimmedName)"
    }

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
    /// Identifier from the static GTFS feed. It remains distinct from an
    /// opaque HAFAS identifier, although ATP currently accepts Luxembourg's
    /// numeric GTFS stop IDs directly when no HAFAS identifier is available.
    let gtfsStopID: String?
    /// One or more opaque HAFAS station identifiers confidently associated
    /// with this canonical stop. A stop can retain no live identifier when the
    /// feeds cannot be matched safely.
    let hafasStationIDs: [String]

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
        gtfsStopID: String? = nil,
        hafasStationIDs: [String] = []
    ) {
        self.id = id
        let displayName = name.stationDisplayName
        self.name = displayName
        self.locality = Self.normalizedLocality(locality, from: name)
        self.location = location
        self.modes = modes
        self.dataSource = dataSource
        self.platformIds = Self.normalizedPlatformIds(platformIds, fallbackId: id)
        self.gtfsStopID = gtfsStopID
        self.hafasStationIDs = Self.normalizedIdentifiers(hafasStationIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case locality
        case location
        case modes
        case dataSource
        case platformIds
        case gtfsStopID
        case hafasStationIDs
    }

    /// Decodes a stop, applying the same platform normalization as the
    /// memberwise initializer so persisted and freshly built stops behave
    /// identically.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)

        self.id = id
        let rawName = try container.decode(String.self, forKey: .name)
        let name = rawName.stationDisplayName
        self.name = name
        locality = Self.normalizedLocality(
            try container.decodeIfPresent(String.self, forKey: .locality),
            from: rawName
        )
        location = try container.decode(LocationPoint.self, forKey: .location)
        modes = try container.decode([TransportMode].self, forKey: .modes)
        dataSource = try container.decode(DataSource.self, forKey: .dataSource)
        platformIds = try Self.normalizedPlatformIds(
            container.decodeIfPresent([String].self, forKey: .platformIds),
            fallbackId: id
        )
        gtfsStopID = try container.decodeIfPresent(String.self, forKey: .gtfsStopID)
        hafasStationIDs = Self.normalizedIdentifiers(
            try container.decodeIfPresent([String].self, forKey: .hafasStationIDs) ?? []
        )
    }

    private nonisolated static func normalizedPlatformIds(_ ids: [String]?, fallbackId: String) -> [String] {
        let normalized = (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? [fallbackId] : Array(dictOrderedSet: normalized)
    }

    private nonisolated static func normalizedIdentifiers(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The rider-facing name without a locality prefix that is already shown
    /// separately in the UI.
    nonisolated var displayName: String {
        let cleanedName = name.stationDisplayName
        let trimmedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality,
              !locality.isEmpty,
              trimmedName.count > locality.count + 1 else {
            return cleanedName
        }

        let prefix = "\(locality),"
        guard trimmedName.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame else {
            return cleanedName
        }

        let strippedName = trimmedName.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return strippedName.isEmpty ? cleanedName : String(strippedName)
    }

    private nonisolated static func normalizedLocality(_ locality: String?, from name: String) -> String? {
        if let locality = locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty {
            return locality
        }

        let firstComponent = name
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstComponent, !firstComponent.isEmpty, name.contains(",") {
            return firstComponent
        }

        guard name.contains("(") else { return nil }
        let nameWithoutQualifier = name
            .components(separatedBy: "(")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        guard let separator = nameWithoutQualifier.lastIndex(of: "-") else { return nil }

        let inferredLocality = nameWithoutQualifier[nameWithoutQualifier.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inferredLocality.isEmpty ? nil : String(inferredLocality)
    }
}

extension Sequence where Element == Stop {
    /// Keeps the first stop for each exact canonical name and set of transport
    /// modes while preserving the source order.
    ///
    /// Feed qualifiers such as "(Bus)" and "(Tram)" are intentionally removed
    /// from ``Stop/name`` for presentation. Including the modes in the key keeps
    /// those otherwise-identically-named stops distinct on the map.
    nonisolated func deduplicatedByExactName() -> [Stop] {
        var seenStops = Set<StopNameDeduplicationKey>()
        return filter {
            seenStops.insert(
                StopNameDeduplicationKey(name: $0.name, modes: Set($0.modes))
            ).inserted
        }
    }
}

private nonisolated struct StopNameDeduplicationKey: Hashable {
    let name: String
    let modes: Set<TransportMode>
}

private extension [String] {
    nonisolated init(dictOrderedSet values: [String]) {
        var seen: Set<String> = []
        self = values.filter { seen.insert($0).inserted }
    }
}
