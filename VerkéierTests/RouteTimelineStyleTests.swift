import Testing
@testable import Verkeier

@Suite("Route timeline styling")
struct RouteTimelineStyleTests {
    @Test("Walking rails never take precedence for a place marker")
    func markerPrefersAdjacentTransitRail() {
        #expect(RouteTimelineRail.preferredDotRail(
            above: .walk,
            below: .transit(.train)
        ) == .transit(.train))
        #expect(RouteTimelineRail.preferredDotRail(
            above: .transit(.bus),
            below: .walk
        ) == .transit(.bus))
    }

    @Test("GTFS tram route types use tram styling")
    func mapsTramRouteTypes() {
        #expect(MobiliteitRouteService.mode(forGTFSRouteType: 0) == .tram)
        #expect(MobiliteitRouteService.mode(forGTFSRouteType: 900) == .tram)
        #expect(MobiliteitRouteService.mode(forGTFSRouteType: 2) == .train)
    }
}
