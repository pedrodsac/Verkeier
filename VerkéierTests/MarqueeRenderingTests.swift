import Observation
import SwiftUI
import Testing
import UIKit
@testable import Verkeier

@MainActor
@Suite("Rendered destination rows", .serialized)
struct MarqueeRenderingTests {
    @Test func boardRefreshAndSheetHeightPreserveRenderedAnimation() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = MarqueeRenderingState()
        let preferences = AppPreferences(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let controller = UIHostingController(rootView: MarqueeRenderingBoard(state: state)
            .environment(preferences).environment(\.scenePhase, .active))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }

        try await Task.sleep(for: .milliseconds(300))
        let marquees = descendants(of: controller.view).compactMap { $0 as? MarqueeLabelView }
        #expect(marquees.count >= 3)
        let moving = marquees.filter { $0.cycle != nil }
        #expect(moving.count >= 2)
        let generations = moving.map(\.animationGeneration)
        state.revision += 1
        state.sheetHeight += 80
        try await Task.sleep(for: .milliseconds(300))
        #expect(moving.map(\.animationGeneration) == generations)
        #expect(moving.allSatisfy { $0.window != nil && $0.cycle != nil })
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor @Observable
private final class MarqueeRenderingState {
    var revision = 0
    var sheetHeight: CGFloat = 480
    let anchor = Date.now
}

private struct MarqueeRenderingBoard: View {
    let state: MarqueeRenderingState
    private let destinations = [
        "Kirchberg, Gare routière Luxexpo — via Aéroport",
        "Bertrange, Belle Étoile — via Luxembourg, Gare Centrale",
        "Clervaux",
        "Luxembourg, Limpertsberg — via Centre, Fondation Pescatore"
    ]

    var body: some View {
        VStack {
            Text("Fixture departures").font(.title2)
            Spacer()
            List {
                ForEach(Array(destinations.enumerated()), id: \.offset) { index, destination in
                    DepartureListRow(departure: Departure(
                        id: "fixture-\(index)", stopId: "fixture-stop", lineName: index == 0 ? "T1" : "16",
                        destination: destination,
                        scheduledDeparture: state.anchor.addingTimeInterval(Double(20 + index + state.revision) * 60),
                        platform: "\(index + 1)", dataSource: .mock
                    ), showsControls: false)
                }
                TimelineSegmentRow(node: SegmentNode(
                    id: "fixture-route", kind: .transit, mode: .bus, badgeText: "16",
                    headsign: destinations[1], durationMinutes: 15, stopCount: 8,
                    distanceMeters: nil, rail: .transit(.bus), bikeShareDetails: nil
                ))
            }
            .listStyle(.plain)
            .frame(height: state.sheetHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
