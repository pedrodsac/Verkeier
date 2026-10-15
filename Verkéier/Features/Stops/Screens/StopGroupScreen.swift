import SwiftUI

/// The stops in a tapped map cluster.
struct StopGroupScreen: View {
    @Environment(MapModel.self) private var map

    var body: some View {
        List(map.selectedStopGroup.deduplicatedByExactName()) { stop in
            NavigationLink(value: SheetRoute.stopDetail(stop)) {
                StopRow(
                    stop: stop,
                    routes: map.nearbyStopRoutes[stop.id] ?? []
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Stops at this location")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    let models = FeatureModels()
    models.map.selectedStopGroup = [
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
    ]
    return NavigationStack {
        StopGroupScreen()
    }
    .previewEnvironment(models)
}
