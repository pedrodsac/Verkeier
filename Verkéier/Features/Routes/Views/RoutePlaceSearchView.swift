import SwiftUI

/// Search destination pushed from a Plan endpoint. The endpoint's current
/// value and the device location stay above the reusable recent places list.
struct RoutePlaceSearchView: View {
    let endpoint: RouteEndpoint
    let viewModel: RoutePresentationModel
    let onSelect: (RoutePlace?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.placeSearchService) private var placeSearchService
    @State private var query = ""
    @State private var results: [RoutePlace] = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedPlace: RoutePlace? {
        viewModel.selectedPlace(for: endpoint)
    }

    var body: some View {
        List {
            pinnedSection

            if !viewModel.recentPlacesExcludingPinned(for: endpoint).isEmpty {
                Section("Recents") {
                    ForEach(viewModel.recentPlacesExcludingPinned(for: endpoint)) { place in
                        placeButton(place)
                    }
                }
            }

            if !trimmedQuery.isEmpty {
                if results.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "mappin.slash",
                            description: Text("Try another stop, address, or place name.")
                        )
                    }
                } else {
                    Section("Results") {
                        ForEach(results) { place in
                            placeButton(place)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(endpoint.searchTitle)
        .toolbarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: endpoint.searchPrompt
        )
        .task(id: query) {
            await updateResults()
        }
    }

    private var pinnedSection: some View {
		Group {
			Button(action: selectCurrentLocation) {
				RoutePlaceSearchRow(
					title: "Current Location",
					subtitle: viewModel.currentLocation?.subtitle ?? "Live device location",
					systemImage: "location.fill",
					tint: .blue
				)
			}
			.disabled(endpoint == .destination && viewModel.currentLocation == nil)
			
			if let selectedPlace,
			   selectedPlace.id != viewModel.currentLocation?.id {
				placeButton(selectedPlace)
			}
		}
    }

    private func placeButton(_ place: RoutePlace) -> some View {
        Button {
            onSelect(place)
            dismiss()
        } label: {
            RoutePlaceSearchRow(
                title: place.title,
                subtitle: place.subtitle,
                systemImage: place.searchSystemImage,
                tint: place.searchIconTint
            )
        }
        .tint(.secondary)
    }

    private func selectCurrentLocation() {
        guard endpoint == .origin || viewModel.currentLocation != nil else { return }
        onSelect(endpoint == .origin ? nil : viewModel.currentLocation)
        dismiss()
    }

    private func updateResults() async {
        let current = trimmedQuery
        guard !current.isEmpty else {
            results = []
            return
        }

        // Debounce: a new keystroke cancels this task before the sleep ends.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        async let stops = gtfsService.searchStops(query: current)
        async let places = placeSearchService.searchPlaces(
            query: current,
            near: viewModel.currentLocation?.location
        )
        let stopResults = await stops
        let stopPlaces = stopResults
            .deduplicatedByExactName()
            .map { RoutePlace(stop: $0, source: .search) }
        let placeResults = await places
        guard !Task.isCancelled else { return }

        var seenIDs = Set<String>()
        results = (stopPlaces + placeResults).filter { seenIDs.insert($0.id).inserted }
    }
}

private extension RoutePlace {
    var searchSystemImage: String {
        guard stopId != nil else { return "mappin.circle.fill" }
        if modes.contains(.train) { return "train.side.front.car" }
        if modes.contains(.bus) { return "bus.fill" }
        if modes.contains(.tram) { return "tram.fill" }
        return "train.side.front.car"
    }

    var searchIconTint: Color {
        guard stopId != nil else { return .red }
        if modes.contains(.train) { return .red }
        if modes.contains(.bus) { return .blue }
        if modes.contains(.tram) { return .orange }
        return .red
    }
}

private struct RoutePlaceSearchRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}
