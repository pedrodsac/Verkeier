import SwiftUI

/// Editable route endpoints with native drag handles for reversing the journey.
struct RouteEndpointsCard: View {
    let viewModel: RoutePresentationModel
    let showRoutePlaceSearch: (RouteEndpoint) -> Void
    let swapRouteEndpoints: () -> Void

    @State private var dragSessionID = UUID()
    @ScaledMetric(relativeTo: .body) private var badgeSize = 32

    var body: some View {
        VStack(spacing: 0) {
            endpointRow(.origin)
            Divider()
                .padding(.leading, badgeSize + 22)
                .padding(.trailing, 12)
            endpointRow(.destination)
        }
        .background(alignment: .leading) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 4, height: 10)
                .padding(.leading, 12 + badgeSize / 2 - 2)
                .accessibilityHidden(true)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func endpointRow(_ endpoint: RouteEndpoint) -> some View {
        let place = viewModel.selectedPlace(for: endpoint)
        let isCurrentLocation = place?.source == .currentLocation || (endpoint == .origin && place == nil)
        return RouteEndpointRow(
            endpoint: endpoint,
            title: isCurrentLocation ? String(localized: "My Location")
                : (endpoint == .origin ? viewModel.originTitle : viewModel.destinationTitle),
            place: place,
            canSwap: viewModel.hasDestination && (viewModel.origin != nil || viewModel.currentLocation != nil),
            dragSessionID: dragSessionID,
            select: { showRoutePlaceSearch(endpoint) },
            swap: swapRouteEndpoints
        )
    }
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        RouteEndpointsCard(
            viewModel: .previewForCard,
            showRoutePlaceSearch: { _ in },
            swapRouteEndpoints: {}
        )
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
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
