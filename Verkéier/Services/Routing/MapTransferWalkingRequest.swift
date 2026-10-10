import Foundation

/// Presentation geometry between rides, independent of timetable walking legs.
nonisolated struct MapTransferWalkingRequest: Sendable {
    static let segmentPrefix = "map-transfer-walk:"
    let id: String
    let geometry: WalkingGeometryRequest

    static func requests(in legs: [RoutePlan.Leg]) -> [Self] {
        zip(legs, legs.dropFirst()).compactMap { incoming, outgoing in
            guard incoming.transportKind == .transit,
                  outgoing.transportKind == .transit,
                  outgoing.continuesInSeatFromTripID == nil,
                  incoming.mapCoordinates.count >= 2,
                  outgoing.mapCoordinates.count >= 2,
                  let from = incoming.mapCoordinates.last,
                  let to = outgoing.mapCoordinates.first,
                  from != to else { return nil }
            // Use the actual shape endpoints, not the aggregate station point.
            let geometry = WalkingGeometryRequest(
                origin: LocationPoint(latitude: from.latitude, longitude: from.longitude),
                destination: LocationPoint(latitude: to.latitude, longitude: to.longitude))
            return Self(id: "\(segmentPrefix)\(incoming.id):\(outgoing.id):\(geometry.key)", geometry: geometry)
        }
    }
}
