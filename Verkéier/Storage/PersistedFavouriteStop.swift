import Foundation
import SwiftData

@Model
final class PersistedFavouriteStop {
    @Attribute(.unique) var stopId: String
    var name: String
    var locality: String?
    var latitude: Double
    var longitude: Double
    var modesRawValue: String
    var platformIdsRawValue: String?
    /// Feed identifiers are persisted separately because GTFS and HAFAS use
    /// unrelated identifier spaces. These additive optional fields preserve
    /// existing favourites while allowing newly saved stops to refresh both
    /// scheduled and live boards after an app relaunch.
    var gtfsStopID: String?
    var hafasStationIDsRawValue: String?
    var createdAt: Date
    /// Optional rider-set grouping label, e.g. "Home", "Work". `nil` = unlabelled.
    var label: String?
    /// Additive storage for multiple rider-defined labels. The legacy `label`
    /// remains populated with the first label so existing stores and older
    /// app versions continue to render a sensible group.
    var labelsData: Data?
    /// Optional saved board scope for this favourite. `nil` preserves the
    /// historical unfiltered favourite behaviour.
    var boardFilterData: Data?
    /// Optional presentation customizations added without disturbing older stores.
    var displayLabel: String?
    var iconName: String?
    var colorHex: String?
    /// Rider-chosen position among the favourites. Optional so existing stores
    /// migrate without a default; `nil` sorts first, then by ``createdAt``.
    var sortOrder: Int?

    /// The order favourites are shown in, everywhere they are listed.
    static let displayOrder: [SortDescriptor<PersistedFavouriteStop>] = [
        SortDescriptor(\.sortOrder),
        SortDescriptor(\.createdAt),
    ]

    init(
        stop: Stop,
        boardFilter: TransitBoardFilter? = nil,
        sortOrder: Int? = nil,
        createdAt: Date = .now
    ) {
        stopId = stop.id
        name = stop.name
        locality = stop.locality
        latitude = stop.location.latitude
        longitude = stop.location.longitude
        modesRawValue = stop.modes.map(\.rawValue).joined(separator: ",")
        platformIdsRawValue = stop.platformIds.joined(separator: ",")
        gtfsStopID = stop.gtfsStopID
        hafasStationIDsRawValue = stop.hafasStationIDs.joined(separator: ",")
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        boardFilterData = boardFilter.flatMap { try? JSONEncoder().encode($0) }
    }

    /// Numbers `favourites` (given in their current display order) so they
    /// follow `stopIDs`. Favourites missing from `stopIDs` keep their relative
    /// order after the listed ones.
    static func applyOrder(_ stopIDs: [String], to favourites: [PersistedFavouriteStop]) {
        let position = Dictionary(stopIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = favourites.enumerated().sorted { lhs, rhs in
            (position[lhs.element.stopId] ?? stopIDs.count + lhs.offset)
                < (position[rhs.element.stopId] ?? stopIDs.count + rhs.offset)
        }
        for (index, favourite) in ordered.map(\.element).enumerated() where favourite.sortOrder != index {
            favourite.sortOrder = index
        }
    }

    /// Points this favourite at another stop while keeping its name, look,
    /// labels, position and creation date. The board filter is dropped because
    /// its platforms and lines belong to the old stop. A name that was just the
    /// old stop's name follows the new stop.
    func replaceStop(with stop: Stop) {
        if displayLabel == self.stop.displayName {
            displayLabel = stop.displayName
        }
        stopId = stop.id
        name = stop.name
        locality = stop.locality
        latitude = stop.location.latitude
        longitude = stop.location.longitude
        modesRawValue = stop.modes.map(\.rawValue).joined(separator: ",")
        platformIdsRawValue = stop.platformIds.joined(separator: ",")
        gtfsStopID = stop.gtfsStopID
        hafasStationIDsRawValue = stop.hafasStationIDs.joined(separator: ",")
        boardFilterData = nil
    }

    var stop: Stop {
        Stop(
            id: stopId,
            name: name,
            locality: locality,
            location: LocationPoint(id: stopId, name: name, latitude: latitude, longitude: longitude),
            modes:
                modesRawValue
                .split(separator: ",")
                .compactMap { TransportMode(rawValue: String($0)) },
            dataSource: gtfsStopID == nil ? (hafasStationIDs.isEmpty ? .local : .atpOpenAPI) : .gtfs,
            platformIds: platformIds,
            gtfsStopID: gtfsStopID,
            hafasStationIDs: hafasStationIDs
        )
    }

    private var platformIds: [String] {
        guard let platformIdsRawValue else { return [stopId] }
        let ids =
            platformIdsRawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ids.isEmpty ? [stopId] : ids
    }

    private var hafasStationIDs: [String] {
        guard let hafasStationIDsRawValue else { return [] }
        return
            hafasStationIDsRawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var labels: [String] {
        let decoded = labelsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        if let decoded, !decoded.isEmpty {
            return Self.normalizedLabels(decoded)
        }
        return Self.normalizedLabels(label.map { [$0] } ?? [])
    }

    var boardFilter: TransitBoardFilter {
        guard let boardFilterData,
            let filter = try? JSONDecoder().decode(TransitBoardFilter.self, from: boardFilterData)
        else {
            return TransitBoardFilter()
        }
        return filter
    }

    func replaceBoardFilter(with filter: TransitBoardFilter) {
        boardFilterData = try? JSONEncoder().encode(filter)
    }

    func replaceLabels(with values: [String]) {
        let normalized = Self.normalizedLabels(values)
        labelsData = try? JSONEncoder().encode(normalized)
        label = normalized.first
    }

    static func normalizedLabels(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }
}
