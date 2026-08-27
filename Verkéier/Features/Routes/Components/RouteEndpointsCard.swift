import SwiftUI

/// An Apple Maps-style unified From/To card with a vertical connector rail
/// and an inline swap button.
///
/// Tapping either endpoint pushes the planner's place search. Tapping outside
/// the endpoint rows is handled by the ``swapRouteEndpoints`` action on the
/// swap button.
struct RouteEndpointsCard: View {
    let viewModel: RoutePresentationModel
    let showRoutePlaceSearch: (RouteEndpoint) -> Void
    let swapRouteEndpoints: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            connectorRail

            VStack(spacing: 0) {
                fromRow
                Divider()
                    .padding(.leading, 2)
                toRow
            }

            swapButton
        }
        .cardSurface(radius: 18)
        // Keep the connector rail from using spare sheet height when the
        // planner is empty. Without this, its flexible marker frames can
        // make the endpoint card grow until routes or a destination appear.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Connector rail

    private var connectorRail: some View {
        VStack(spacing: 0) {
            // Origin dot — sits in the centre of the From row
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .frame(maxHeight: .infinity)

            // Destination pin — sits in the centre of the To row
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxHeight: .infinity)
        }
        .background(alignment: .center) {
            // Vertical line connecting the two markers
            Rectangle()
                .fill(.separator.opacity(0.55))
                .frame(width: 1.5)
                .padding(.vertical, 30)
        }
        .frame(width: 40)
        .accessibilityHidden(true)
    }

    // MARK: - Endpoint rows

    private var fromRow: some View {
        Button {
            showRoutePlaceSearch(.origin)
        } label: {
            endpointLabel(
                tag: "FROM",
                title: viewModel.originTitle,
                subtitle: viewModel.originSubtitle
            )
        }
        .buttonStyle(.plain)
    }

    private var toRow: some View {
        Button {
            showRoutePlaceSearch(.destination)
        } label: {
            endpointLabel(
                tag: "TO",
                title: viewModel.destinationTitle,
                subtitle: viewModel.destinationSubtitle
            )
        }
        .buttonStyle(.plain)
    }

    private func endpointLabel(tag: String, title: String, subtitle _: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tag)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .kerning(0.3)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    // MARK: - Swap button

    private var swapButton: some View {
        Button(action: swapRouteEndpoints) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(viewModel.hasDestination ? Color.blue : Color.secondary.opacity(0.4))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasDestination)
        .accessibilityLabel("Swap origin and destination")
        .padding(.trailing, 4)
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
                    source: .selectedStop
                ),
                currentLocation: nil,
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
