#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import SwiftUI
import MobiliteitKit

struct SimulatorRouteBenchmarkView: View {
    @State private var benchmark = SimulatorRouteBenchmark()
    @State private var navigation = TransitSheetNavigationState()
    @Environment(\.routeService) private var service
    @Environment(\.walkingRouter) private var walking
    @Environment(\.bikeShareService) private var bikes
    var body: some View {
        Group {
            if benchmark.fullMap {
                TransitMapLayer(viewModel: benchmark.viewModel, navigation: navigation,
                    favouriteStopIds: [], bikeShareStations: [], selectStop: { _ in },
                    selectStopGroup: { _, _ in }, regionDidChange: { _ in })
                .overlay {
                    if let request = benchmark.viewModel.routeDiagnostics?.requestID {
                        RouteRenderObserver(requestID: request) { id in benchmark.recordMapRendered(id) }
                            .frame(width: 0, height: 0)
                    }
                }
            } else {
                Color.clear
            }
        }.onChange(of: benchmark.viewModel.selectedRouteOptionID) { _, id in
            navigation.selectedTab = .plan
            navigation.planPath = id.map { [.routeTimeline($0)] } ?? []
        }.sheet(isPresented: .constant(true)) {
            ScrollView {
                Text(benchmark.status).font(.caption).padding()
                RouteView(viewModel: benchmark.presentation, actions: RouteActions()).padding()
            }.presentationDetents([.large]).interactiveDismissDisabled()
        }.task { await benchmark.run(productionService: service, walkingRouter: walking, bikes: bikes) }
    }
}

#endif
