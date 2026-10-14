import Foundation
import MobiliteitKit

/// Expands a measured station connection for presentation while the native
/// search retains it as one continuous transfer (and preserves its full time).
nonisolated enum StationConnectionLegMapper {
    static func legs(from original: RoutePlan.Leg, segments: [WalkingRouteSegment]) -> [RoutePlan.Leg] {
        guard !segments.isEmpty, segments.contains(where: { $0.mode == .funicular }),
            let departure = original.departureTime, let arrival = original.arrivalTime,
            segments.allSatisfy({
                $0.durationSeconds >= 0 && $0.distanceMeters.isFinite
                    && $0.distanceMeters >= 0 && $0.polyline.count >= 2
            }),
            abs(
                Double(segments.reduce(0) { $0 + $1.durationSeconds })
                    - arrival.timeIntervalSince(departure)
            ) <= 1
        else { return [original] }
        var cursor = departure
        return segments.enumerated().map { index, segment in
            let first = segment.polyline.first!
            let last = segment.polyline.last!
            let origin =
                index == 0
                ? original.origin
                : LocationPoint(
                    name: segment.originLabel,
                    latitude: first.latitude,
                    longitude: first.longitude
                )
            let destination =
                index == segments.count - 1
                ? original.destination
                : LocationPoint(name: segment.destinationLabel, latitude: last.latitude, longitude: last.longitude)
            let end =
                index == segments.count - 1
                ? arrival
                : cursor.addingTimeInterval(Double(segment.durationSeconds))
            defer { cursor = end }
            var leg = RoutePlan.Leg(
                id: "\(original.id)-segment-\(index)",
                mode: segment.mode == .funicular ? .funicular : .walking,
                transportKind: segment.mode == .funicular ? .transit : .walking,
                routeName: segment.name,
                headsign: segment.mode == .funicular ? destination.name : nil,
                origin: origin,
                destination: destination,
                departureTime: cursor,
                arrivalTime: end,
                distanceMeters: segment.distanceMeters,
                mapCoordinates: segment.polyline.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                roadRoutingHint: .none
            )
            leg.walkingEvidence = segment.mode == .walking ? original.walkingEvidence : nil
            // These are already measured subpaths of one native transfer. Do
            // not feed one subpath back as a replacement for the whole transfer.
            return leg
        }
    }
}
