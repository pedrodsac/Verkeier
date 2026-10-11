import SwiftUI

/// Native endpoint rows hosted directly by the planner's list.
struct RouteEndpointsSection: View {
    let viewModel: RoutePresentationModel
    let showRoutePlaceSearch: (RouteEndpoint) -> Void
    let swapRouteEndpoints: () -> Void

    // Identity follows each moved row; its position defines the endpoint role.
    @State private var rowIDs = [UUID(), UUID()]
    @ScaledMetric(relativeTo: .body) private var badgeSize = 24

    var body: some View {
        Section {
            ForEach(rowIDs.enumerated(), id: \.element) { index, _ in
                let endpoint: RouteEndpoint = index == 0 ? .origin : .destination
                endpointRow(endpoint)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in badgeSize + 10 }
                    .moveDisabled(!canSwap)
            }
            .onMove(perform: moveEndpoints)
            .environment(\.editMode, .constant(.active))
        }
    }

    private var canSwap: Bool {
        viewModel.hasDestination && (viewModel.origin != nil || viewModel.currentLocation != nil)
    }

    private func moveEndpoints(from source: IndexSet, to destination: Int) {
        guard canSwap,
              (source == IndexSet(integer: 0) && destination == 2)
                || (source == IndexSet(integer: 1) && destination == 0) else { return }
        rowIDs.move(fromOffsets: source, toOffset: destination)
        swapRouteEndpoints()
    }

    private func endpointRow(_ endpoint: RouteEndpoint) -> some View {
        let place = viewModel.selectedPlace(for: endpoint)
        let isCurrentLocation = place?.source == .currentLocation || (endpoint == .origin && place == nil)
        return RouteEndpointRow(
            endpoint: endpoint,
            title: isCurrentLocation ? String(localized: "My Location")
                : (endpoint == .origin ? viewModel.originTitle : viewModel.destinationTitle),
            place: place,
            canSwap: canSwap,
            select: { showRoutePlaceSearch(endpoint) },
            swap: swapRouteEndpoints
        )
    }
}

#if DEBUG
    #Preview {
        List {
            RouteEndpointsSection(
                viewModel: .previewForCard,
                showRoutePlaceSearch: { _ in },
                swapRouteEndpoints: {}
            )
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private extension RoutePresentationModel {
        static var previewForCard: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: Stop(
                    id: "stop-luxexpo",
                    name: "Luxexpo",
                    locality: "Kirchberg",
                    location: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                    modes: [.tram, .bus],
                    dataSource: .mock
                ),
                origin: nil,
                destination: RoutePlace(
                    title: "Luxexpo",
                    subtitle: "Kirchberg",
                    location: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                    stopId: "stop-luxexpo",
                    modes: [.tram, .bus],
                    source: .selectedStop
                ),
                currentLocation: .currentLocation(
                    LocationPoint(name: "Current Location", latitude: 49.61, longitude: 6.13)
                ),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: nil
            )
        }
    }
#endif
