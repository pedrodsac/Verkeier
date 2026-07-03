import SwiftUI
import Testing
@testable import LuxTransit

/// Smoke test: the redesigned route-detail views must rasterise without
/// crashing for a full multi-transfer journey (all place roles, a delayed tight
/// transfer, walks). Guards the render path — layout cycles or a nil marker
/// surface here fail loudly rather than in production.
@MainActor
struct RouteTimelineSnapshotTests {
    // Future-relative so the option resolves to a live "Tight transfer" rather
    // than "Missed", and every time is monotonic.
    private let base = Date().addingTimeInterval(8 * 60)
    private func t(_ minutes: Int) -> Date {
        base.addingTimeInterval(Double(minutes) * 60)
    }

    private func point(_ name: String) -> LocationPoint {
        LocationPoint(id: name, name: name, latitude: 49.61, longitude: 6.13)
    }

    /// Mirrors the user's screenshot: walk → 321 → (tight transfer +7) → 211 → 12 → walk.
    private var option: RouteOption {
        let legs: [RoutePlan.Leg] = [
            RoutePlan.Leg(
                id: "w1", mode: .walking, transportKind: .walking,
                origin: point("Senningerberg, Gromscheed"),
                destination: point("Senningerberg, Charlys Statioun"),
                departureTime: t(0), arrivalTime: t(5), distanceMeters: 390
            ),
            RoutePlan.Leg(
                id: "b321", mode: .bus, transportKind: .transit, routeName: "321",
                headsign: "Kirchberg, Gare routière Luxexpo",
                origin: point("Senningerberg, Charlys Statioun"),
                destination: point("Kirchberg, Gare routière Luxexpo"),
                departureTime: t(11), arrivalTime: t(26), platform: "2", liveStatus: .scheduled
            ),
            RoutePlan.Leg(
                id: "b211", mode: .bus, transportKind: .transit, routeName: "211",
                headsign: "Limpertsberg, Theater",
                origin: point("Kirchberg, Gare routière Luxexpo"),
                destination: point("Kirchberg, Rout Bréck - Pafendall"),
                departureTime: t(28),
                arrivalTime: t(40),
                realtimeDepartureTime: t(29),
                realtimeArrivalTime: t(41),
                platform: "5", delayMinutes: 7, liveStatus: .delayed,
                transferWarning: "Connection may be missed"
            ),
            RoutePlan.Leg(
                id: "b12", mode: .bus, transportKind: .transit, routeName: "12",
                headsign: "Merl, Celtes",
                origin: point("Kirchberg, Rout Bréck - Pafendall"),
                destination: point("Hamilius"),
                departureTime: t(44), arrivalTime: t(49), platform: "2", liveStatus: .scheduled
            ),
            RoutePlan.Leg(
                id: "w2", mode: .walking, transportKind: .walking,
                origin: point("Hamilius"),
                destination: point("Hamilius, Roude Pëtz"),
                departureTime: t(49), arrivalTime: t(50), distanceMeters: 47
            )
        ]
        let plan = RoutePlan(
            id: "plan", origin: legs.first!.origin, destination: legs.last!.destination,
            expectedTravelTime: 39 * 60, distanceMeters: 8900, legs: legs, dataSource: .mock
        )
        return RouteOption(id: "opt", plan: plan, mapOverlay: nil)
    }

    private func rasterises(@ViewBuilder _ view: () -> some View) -> Bool {
        let renderer = ImageRenderer(content: view().frame(width: 390).padding(16))
        renderer.scale = 3
        return renderer.uiImage != nil
    }

    @Test func summaryCardRasterises() {
        #expect(rasterises { RouteTimelineSummaryCard(option: option) })
    }

    @Test func timelineRasterises() {
        #expect(rasterises { RouteLegList(legs: option.plan.legs) })
    }
}
