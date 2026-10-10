import CoreGraphics
import Foundation

/// Screen-space layout independent of MapKit, suitable for deterministic tests.
nonisolated enum RouteTraceLayout {
    struct StopInput {
        let id: String
        let point: CGPoint
        let diameter: CGFloat
        let labelSize: CGSize
        let isKey: Bool
    }

    struct ShieldInput {
        let id: String
        let candidates: [CGPoint]
        let size: CGSize
    }

    struct StopPlacement: Equatable {
        let showsCircle: Bool
        let labelFrame: CGRect?
    }

    struct Result {
        var stops: [String: StopPlacement] = [:]
        var shields: [String: CGPoint] = [:]
    }

    static func layout(bounds: CGRect, stops: [StopInput], shields: [ShieldInput],
                       showsIntermediate: Bool) -> Result {
        let bounds = bounds.insetBy(dx: 8, dy: 8)
        var result = Result()
        var occupied: [CGRect] = []
        let visible = stops.filter { bounds.contains($0.point) }
        let keys = visible.filter(\.isKey)
        for stop in keys {
            occupied.append(circleFrame(stop).insetBy(dx: -3, dy: -3))
            result.stops[stop.id] = StopPlacement(showsCircle: true, labelFrame: nil)
        }
        for stop in keys {
            let label = labelFrame(stop, bounds: bounds, occupied: occupied)
            if let label { occupied.append(label.insetBy(dx: -3, dy: -3)) }
            result.stops[stop.id] = StopPlacement(showsCircle: true, labelFrame: label)
        }
        for shield in shields {
            if let point = shield.candidates.first(where: { point in
                fits(centeredFrame(at: point, size: shield.size), bounds: bounds, occupied: occupied)
            }) {
                result.shields[shield.id] = point
                occupied.append(centeredFrame(at: point, size: shield.size).insetBy(dx: -5, dy: -5))
            }
        }
        guard showsIntermediate else { return result }
        for stop in visible where !stop.isKey {
            let circle = circleFrame(stop)
            guard fits(circle.insetBy(dx: -4, dy: -4), bounds: bounds, occupied: occupied) else { continue }
            occupied.append(circle.insetBy(dx: -3, dy: -3))
            let label = labelFrame(stop, bounds: bounds, occupied: occupied)
            if let label { occupied.append(label.insetBy(dx: -3, dy: -3)) }
            result.stops[stop.id] = StopPlacement(showsCircle: true, labelFrame: label)
        }
        return result
    }

    private static func labelFrame(_ stop: StopInput, bounds: CGRect, occupied: [CGRect]) -> CGRect? {
        guard stop.labelSize.width > 4 else { return nil }
        let gap = stop.diameter / 2 + 5
        for x in [stop.point.x + gap, stop.point.x - gap - stop.labelSize.width] {
            let frame = CGRect(origin: CGPoint(x: x, y: stop.point.y - stop.labelSize.height / 2), size: stop.labelSize)
            if fits(frame, bounds: bounds, occupied: occupied) { return frame }
        }
        return nil
    }

    private static func circleFrame(_ stop: StopInput) -> CGRect {
        centeredFrame(at: stop.point, size: CGSize(width: stop.diameter, height: stop.diameter))
    }

    private static func centeredFrame(at point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    private static func fits(_ frame: CGRect, bounds: CGRect, occupied: [CGRect]) -> Bool {
        bounds.contains(frame) && !occupied.contains { $0.intersects(frame) }
    }

    /// Clip to the viewport before measuring: the route's geographic midpoint
    /// may be offscreen, and the midpoint of a bounding box may not be on-route.
    static func shieldCandidates(points: [CGPoint], bounds: CGRect) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        var paths: [[CGPoint]] = []
        for index in 1..<points.count {
            guard let (a, b) = clipped(points[index - 1], points[index], to: bounds) else { continue }
            if paths.last?.last == a { paths[paths.count - 1].append(b) }
            else { paths.append([a, b]) }
        }
        let measured = paths.map { path in
            (path, zip(path, path.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) })
        }.sorted { $0.1.reduce(0, +) > $1.1.reduce(0, +) }
        return measured.flatMap { path, lengths -> [CGPoint] in
            let total = lengths.reduce(0, +)
            guard total >= 40 else { return [] }
            return [0.5, 0.35, 0.65, 0.2, 0.8].compactMap { fraction in
                var remaining = total * fraction
                for (index, length) in lengths.enumerated() where length > 0 {
                    if remaining <= length {
                        let a = path[index], b = path[index + 1]
                        return CGPoint(x: a.x + (b.x - a.x) * remaining / length,
                            y: a.y + (b.y - a.y) * remaining / length)
                    }
                    remaining -= length
                }
                return nil
            }
        }
    }

    private static func clipped(_ a: CGPoint, _ b: CGPoint, to bounds: CGRect) -> (CGPoint, CGPoint)? {
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        var start: CGFloat = 0, end: CGFloat = 1
        for (p, q) in [(-dx, a.x - bounds.minX), (dx, bounds.maxX - a.x),
                       (-dy, a.y - bounds.minY), (dy, bounds.maxY - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            let ratio = q / p
            if p < 0 { start = max(start, ratio) } else { end = min(end, ratio) }
            if start > end { return nil }
        }
        return (CGPoint(x: a.x + start * dx, y: a.y + start * dy),
                CGPoint(x: a.x + end * dx, y: a.y + end * dy))
    }
}
