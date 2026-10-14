import SwiftUI

struct StopGroupView: View {
    let viewModel: StopGroupPresentationModel

    var body: some View {
        List(viewModel.stops) { stop in
            NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
                StopRow(
                    stop: stop,
                    routes: viewModel.routesByStopId[stop.id] ?? []
                )
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    StopGroupView(
        viewModel: StopGroupPresentationModel(
            stops: [
                Stop(
                    id: "stop-1",
                    name: "Hamilius-Centre (Tram)",
                    locality: "Luxembourg",
                    location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
                    modes: [.tram],
                    dataSource: .mock
                ),
                Stop(
                    id: "stop-2",
                    name: "Hamilius-Centre (Bus)",
                    locality: "Luxembourg",
                    location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
                    modes: [.bus],
                    dataSource: .mock
                ),
            ],
            bikeShareStations: [],
            referenceLocation: nil,
            routesByStopId: [:]
        ),
    )
    .padding(.horizontal, 16)
}
