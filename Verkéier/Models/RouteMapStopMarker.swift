import Foundation

nonisolated struct RouteMapStopMarker: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case intermediate, boarding, alighting, transfer, terminus
    }

    let id: String
    let stopID: String?
    let name: String
    let coordinate: RouteMapCoordinate
    let segmentIDs: [String]
    let mode: TransportMode
    let role: Role
    let emphasis: RouteMapEmphasis?

    init(id: String, stopID: String? = nil, name: String, coordinate: RouteMapCoordinate,
         segmentIDs: [String], mode: TransportMode, role: Role, emphasis: RouteMapEmphasis? = nil) {
        self.id = id
        self.stopID = stopID
        self.name = name
        self.coordinate = coordinate
        self.segmentIDs = segmentIDs
        self.mode = mode
        self.role = role
        self.emphasis = emphasis
    }
}
