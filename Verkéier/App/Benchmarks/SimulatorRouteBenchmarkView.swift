#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import SwiftUI
import MobiliteitKit

struct SimulatorRouteBenchmarkView: View {
    @State private var benchmark = SimulatorRouteBenchmark()
    @Environment(\.routeService) private var service
    @Environment(\.walkingRouter) private var walking
    @Environment(\.bikeShareService) private var bikes
    var body: some View {
        Group {
            if benchmark.fullMap {
                TransitMapLayer(
                    favouriteStopIds: [],
                    bikeShareStations: [],
                    selectStop: { _ in },
                    selectStopGroup: { _, _ in },
                    regionDidChange: { _ in }
                )
                .featureModels(benchmark.featureModels)
                .environment(benchmark.router)
                .overlay {
                    if let request = benchmark.routePlanner.routeDiagnostics?.requestID {
                        RouteRenderObserver(requestID: request) { id in benchmark.recordMapRendered(id) }
                            .frame(width: 0, height: 0)
                    }
                }
            } else {
                Color.clear
            }
        }.onChange(of: benchmark.routePlanner.selectedRouteOptionID) { _, id in
            benchmark.router.selectedTab = .plan
            benchmark.router.planPath = id.map { [.routeTimeline($0)] } ?? []
        }.sheet(isPresented: .constant(true)) {
            ScrollView {
                Text(benchmark.status).font(.caption).padding()
                RouteView().padding()
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled()
            .featureModels(benchmark.featureModels)
            .environment(benchmark.router)
            .environment(benchmark.router.locationService)
        }.task { await benchmark.run(productionService: service, walkingRouter: walking, bikes: bikes) }
    }
}

#endif
