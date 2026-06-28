import SwiftUI

/// An Apple Maps-style unified From/To card with a vertical connector rail
/// and an inline swap button.
///
/// The card hosts two `Menu`s (origin and destination) whose content is derived
/// from the view model — favourites, nearby stops, recent places, and the
/// currently selected stop. Tapping outside the menus is handled by the
/// ``swapRouteEndpoints`` action on the swap button.
struct RouteEndpointsCard: View {
    let viewModel: RoutePresentationModel
    let selectRouteOrigin: (RoutePlace?) -> Void
    let selectRouteDestination: (RoutePlace) -> Void
    let swapRouteEndpoints: () -> Void

    @Environment(\.gtfsService) private var gtfsService
    @State private var showOriginSearch = false
    @State private var showDestinationSearch = false

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
        .background(
            .background.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.22), lineWidth: 0.5)
        }
        .sheet(isPresented: $showOriginSearch) {
            RouteStopSearchSheet(title: "Search Origin", gtfsService: gtfsService) { stop in
                selectRouteOrigin(RoutePlace(stop: stop, source: .search))
                showOriginSearch = false
            }
        }
        .sheet(isPresented: $showDestinationSearch) {
            RouteStopSearchSheet(title: "Search Destination", gtfsService: gtfsService) { stop in
                selectRouteDestination(RoutePlace(stop: stop, source: .search))
                showDestinationSearch = false
            }
        }
    }

    // MARK: - Connector rail

    private var connectorRail: some View {
        VStack(spacing: 0) {
            // Origin dot — sits in the centre of the From row
            Circle()
                .fill(.background.opacity(0.2))
                .overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .frame(maxHeight: .infinity)

            // Destination pin — sits in the centre of the To row
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .center) {
            // Vertical line connecting the two markers
            Rectangle()
                .fill(.separator.opacity(0.55))
                .frame(width: 1.5)
                .padding(.vertical, 30)
        }
        .frame(width: 40)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    // MARK: - Endpoint rows

    private var fromRow: some View {
        Menu {
            Button("Current Location") {
                selectRouteOrigin(nil)
            }

            Button {
                showOriginSearch = true
            } label: {
                Label("Search stops…", systemImage: "magnifyingglass")
            }

            if !viewModel.favouritePlaces.isEmpty {
                Section("Favourite Stops") {
                    ForEach(viewModel.favouritePlaces) { place in
                        Button(place.title) { selectRouteOrigin(place) }
                    }
                }
            }

            if !viewModel.recentPlaces.isEmpty {
                Section("Recent Places") {
                    ForEach(viewModel.recentPlaces) { place in
                        Button(place.title) { selectRouteOrigin(place) }
                    }
                }
            }
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
        Menu {
            if let selectedStop = viewModel.selectedStop {
                Button(selectedStop.name) {
                    selectRouteDestination(
                        RoutePlace(stop: selectedStop, source: .selectedStop)
                    )
                }
            }

            Button {
                showDestinationSearch = true
            } label: {
                Label("Search stops…", systemImage: "magnifyingglass")
            }

            if !viewModel.favouritePlaces.isEmpty {
                Section("Favourite Stops") {
                    ForEach(viewModel.favouritePlaces) { place in
                        Button(place.title) { selectRouteDestination(place) }
                    }
                }
            }

            if !viewModel.nearbyPlaces.isEmpty {
                Section("Nearby Stops") {
                    ForEach(Array(viewModel.nearbyPlaces.prefix(6))) { place in
                        Button(place.title) { selectRouteDestination(place) }
                    }
                }
            }

            if !viewModel.recentPlaces.isEmpty {
                Section("Recent Places") {
                    ForEach(viewModel.recentPlaces) { place in
                        Button(place.title) { selectRouteDestination(place) }
                    }
                }
            }
        } label: {
            endpointLabel(
                tag: "TO",
                title: viewModel.destinationTitle,
                subtitle: viewModel.destinationSubtitle
            )
        }
        .buttonStyle(.plain)
    }

    private func endpointLabel(tag: String, title: String, subtitle: String?) -> some View {
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

// MARK: - Stop search sheet

/// A self-contained stop-search sheet for picking a trip origin or destination.
///
/// Mirrors the search field + results list of ``SearchView`` but queries the
/// local GTFS service directly and reports the chosen ``Stop`` via ``onSelect``.
private struct RouteStopSearchSheet: View {
    let title: String
    let gtfsService: any GTFSService
    let onSelect: (Stop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Stop] = []
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                    .padding(.horizontal)
                    .padding(.top, 8)

                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search stops",
                        systemImage: "magnifyingglass",
                        description: Text("Start typing to find a stop from local data.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "tram",
                        description: Text("Try another stop name.")
                    )
                } else {
                    List(results) { stop in
                        Button {
                            onSelect(stop)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let locality = stop.locality {
                                    Text(locality)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: query) {
            let current = trimmedQuery
            guard !current.isEmpty else {
                results = []
                return
            }
            // Debounce: a new keystroke cancels this task before the sleep ends.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = await gtfsService.searchStops(query: current)
        }
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .accessibilityLabel("Stop search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        RouteEndpointsCard(
            viewModel: .previewForCard,
            selectRouteOrigin: { _ in },
            selectRouteDestination: { _ in },
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
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: nil
            )
        }
    }
#endif
