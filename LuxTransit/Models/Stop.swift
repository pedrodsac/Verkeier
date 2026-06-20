import Foundation

struct Stop: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let locality: String?
    let location: LocationPoint
    let modes: [TransportMode]
    let dataSource: DataSource
    let platformIds: [String]

    nonisolated init(
        id: String,
        name: String,
        locality: String? = nil,
        location: LocationPoint,
        modes: [TransportMode] = [],
        dataSource: DataSource,
        platformIds: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.locality = locality
        self.location = location
        self.modes = modes
        self.dataSource = dataSource
        self.platformIds = Self.normalizedPlatformIds(platformIds, fallbackId: id)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case locality
        case location
        case modes
        case dataSource
        case platformIds
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)

        self.id = id
        name = try container.decode(String.self, forKey: .name)
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        location = try container.decode(LocationPoint.self, forKey: .location)
        modes = try container.decode([TransportMode].self, forKey: .modes)
        dataSource = try container.decode(DataSource.self, forKey: .dataSource)
        platformIds = Self.normalizedPlatformIds(
            try container.decodeIfPresent([String].self, forKey: .platformIds),
            fallbackId: id
        )
    }

    private nonisolated static func normalizedPlatformIds(_ ids: [String]?, fallbackId: String) -> [String] {
        let normalized = (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? [fallbackId] : Array(dictOrderedSet: normalized)
    }
}

private extension Array where Element == String {
    nonisolated init(dictOrderedSet values: [String]) {
        var seen: Set<String> = []
        self = values.filter { seen.insert($0).inserted }
    }
}
