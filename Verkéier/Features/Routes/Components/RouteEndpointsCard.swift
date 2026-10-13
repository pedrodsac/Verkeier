import SwiftUI

/// Editable route endpoints with native drag handles for reversing the journey.
struct RouteEndpointsCard: View {
    let viewModel: RoutePresentationModel
    let showRoutePlaceSearch: (RouteEndpoint) -> Void
    let swapRouteEndpoints: () -> Void

    // Stable row identities let List animate the actual move while the endpoint
    // at each position continues to represent the route's origin or destination.
    @State private var rowIDs = [UUID(), UUID()]
    @State private var rowHeights: [RouteEndpoint: CGFloat] = [:]
    @ScaledMetric(relativeTo: .body) private var badgeSize = 32

    var body: some View {
        List {
            ForEach(rowIDs.enumerated(), id: \.element) { index, _ in
                let endpoint: RouteEndpoint = index == 0 ? .origin : .destination
                endpointRow(endpoint)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        rowHeights[endpoint] = height
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(endpoint == .origin ? .visible : .hidden, edges: .bottom)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in badgeSize + 10 }
            }
            .onMove(perform: moveEndpoints)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .environment(\.defaultMinListRowHeight, 0)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .contentMargins(0)
        .frame(height: cardHeight)
        .background(alignment: .topLeading) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 4, height: 10)
                .offset(x: 12 + badgeSize / 2 - 2, y: originRowHeight - 5)
                .accessibilityHidden(true)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 22))
    }

    private var canSwap: Bool {
        viewModel.hasDestination && (viewModel.origin != nil || viewModel.currentLocation != nil)
    }

    private var originRowHeight: CGFloat {
        rowHeights[.origin] ?? badgeSize + 16
    }

    private var cardHeight: CGFloat {
        originRowHeight + (rowHeights[.destination] ?? badgeSize + 16)
    }

    private func moveEndpoints(from source: IndexSet, to destination: Int) {
        guard (source == IndexSet(integer: 0) && destination == 2)
                || (source == IndexSet(integer: 1) && destination == 0) else { return }
        guard canSwap else {
            revertRejectedMove(from: source, to: destination)
            return
        }
        rowIDs.move(fromOffsets: source, toOffset: destination)
        swapRouteEndpoints()
    }

    /// Without a destination the origin can't take its place, so let the rows
    /// swap visibly and then animate them back to their original positions.
    private func revertRejectedMove(from source: IndexSet, to destination: Int) {
        let original = rowIDs
        rowIDs.move(fromOffsets: source, toOffset: destination)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.snappy) { rowIDs = original }
        }
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
