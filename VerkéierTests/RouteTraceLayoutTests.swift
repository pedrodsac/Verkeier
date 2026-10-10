import CoreGraphics
import Testing
@testable import Verkeier

struct RouteTraceLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 320, height: 400)

    @Test func keyStopsSurviveOverviewAndIntermediateStopsWaitForZoom() {
        let inputs = [stop("board", at: .init(x: 60, y: 100)),
                      stop("middle", at: .init(x: 60, y: 200), key: false)]
        let overview = RouteTraceLayout.layout(bounds: bounds, stops: inputs, shields: [], showsIntermediate: false)
        #expect(overview.stops["board"]?.showsCircle == true)
        #expect(overview.stops["middle"] == nil)
        let close = RouteTraceLayout.layout(bounds: bounds, stops: inputs, shields: [], showsIntermediate: true)
        #expect(close.stops["middle"]?.showsCircle == true)
    }

    @Test func labelsTryLeftSideAndStayWithinViewport() throws {
        let input = stop("edge", at: .init(x: 280, y: 100))
        let result = RouteTraceLayout.layout(bounds: bounds, stops: [input], shields: [], showsIntermediate: true)
        let frame = try #require(result.stops["edge"]?.labelFrame)
        #expect(frame.maxX < input.point.x)
        #expect(bounds.contains(frame))
    }

    @Test func keyCirclesWinOverNamesShieldsAndIntermediateStops() {
        let inputs = [stop("one", at: .init(x: 80, y: 100)), stop("two", at: .init(x: 90, y: 100)),
                      stop("middle", at: .init(x: 85, y: 100), key: false)]
        let shield = RouteTraceLayout.ShieldInput(id: "line", candidates: [.init(x: 85, y: 100)], size: .init(width: 28, height: 18))
        let result = RouteTraceLayout.layout(bounds: bounds, stops: inputs, shields: [shield], showsIntermediate: true)
        #expect(result.stops["one"]?.showsCircle == true)
        #expect(result.stops["two"]?.showsCircle == true)
        #expect(result.stops["middle"] == nil)
        #expect(result.shields.isEmpty)
    }

    @Test func shieldUsesAlternateCandidateWhenMidpointIsOccupied() {
        let shield = RouteTraceLayout.ShieldInput(id: "line", candidates: [.init(x: 80, y: 100), .init(x: 80, y: 240)],
            size: .init(width: 28, height: 18))
        let result = RouteTraceLayout.layout(bounds: bounds, stops: [stop("key", at: .init(x: 80, y: 100))],
            shields: [shield], showsIntermediate: true)
        #expect(result.shields["line"] == CGPoint(x: 80, y: 240))
    }

    @Test func shieldClipsCrossingRouteAndStaysOnItsGeometry() {
        let points = [CGPoint(x: -500, y: 200), CGPoint(x: 1_000, y: 200)]
        let candidates = RouteTraceLayout.shieldCandidates(points: points, bounds: bounds)
        #expect(candidates.first == CGPoint(x: 160, y: 200))
        #expect(candidates.allSatisfy { bounds.contains($0) && $0.y == 200 })
        let bend = RouteTraceLayout.shieldCandidates(points: [.init(x: 40, y: 40), .init(x: 40, y: 240), .init(x: 240, y: 240)], bounds: bounds)
        #expect(bend.allSatisfy { $0.x == 40 || $0.y == 240 })
    }

    @Test func shortMissingAndOffscreenPathsHaveNoShield() {
        for points: [CGPoint] in [[], [.zero], [.init(x: 40, y: 40), .init(x: 50, y: 40)],
                                 [.init(x: -60, y: -50), .init(x: -60, y: -200)]] {
            #expect(RouteTraceLayout.shieldCandidates(points: points, bounds: bounds).isEmpty)
        }
    }

    @Test func oversizedNamesHideWithoutHidingTheirStops() {
        let input = RouteTraceLayout.StopInput(id: "long", point: .init(x: 160, y: 100), diameter: 12,
            labelSize: .init(width: 400, height: 80), isKey: true)
        let result = RouteTraceLayout.layout(bounds: bounds, stops: [input], shields: [], showsIntermediate: true)
        #expect(result.stops["long"]?.showsCircle == true)
        #expect(result.stops["long"]?.labelFrame == nil)
    }

    private func stop(_ id: String, at point: CGPoint, key: Bool = true) -> RouteTraceLayout.StopInput {
        .init(id: id, point: point, diameter: key ? 12 : 8, labelSize: .init(width: 90, height: 30), isKey: key)
    }
}
