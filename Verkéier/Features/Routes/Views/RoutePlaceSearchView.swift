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
    @State private var isSearching = false
    @State private var isSearchActive = true
    @State private var focusSearch = true

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedPlace: RoutePlace? {
        viewModel.selectedPlace(for: endpoint)
    }

    var body: some View {
        // Keep the search bar in a stable host while the results content changes.
        // Replacing the root conditional view on the first keystroke can otherwise
        // recreate the UIKit search bar and resign its first responder.
        ZStack(alignment: .top) {
            searchContent
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            StopSearchBar(
                text: $query,
                isActive: $isSearchActive,
                focusRequested: $focusSearch,
                placeholder: endpoint.searchPrompt,
                accessibilityIdentifier: "route-place-search",
                accessibilityLabel: endpoint.searchTitle,
                onActivate: {},
                onCancel: dismiss.callAsFunction
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .onAppear {
            isSearchActive = true
            focusSearch = true
        }
        .task(id: query) {
            await updateResults()
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if trimmedQuery.isEmpty {
            List {
                Section {
                    currentLocationButton

                    if let selectedPlace,
                       selectedPlace.id != viewModel.currentLocation?.id {
                        placeButton(selectedPlace)
                    }
                }

                let recents = viewModel.recentPlacesExcludingPinned(for: endpoint)
                if !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { place in
                            placeButton(place)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        } else if isSearching && results.isEmpty {
            ProgressView("Searching")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "mappin.slash",
                description: Text("Try another stop, address, or place name.")
            )
        } else {
            List {
                Section {
                    ForEach(results) { place in
                        placeButton(place)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var currentLocationButton: some View {
        Button(action: selectCurrentLocation) {
            RoutePlaceRow(
                title: "Current Location",
                subtitle: viewModel.currentLocation?.subtitle ?? "Live device location",
                systemImage: "location.fill",
                tint: .blue
            )
        }
        .buttonStyle(.plain)
        .disabled(endpoint == .destination && viewModel.currentLocation == nil)
    }

    private func placeButton(_ place: RoutePlace) -> some View {
        Button {
            onSelect(place)
            dismiss()
        } label: {
            RoutePlaceRow(
                title: place.title,
                subtitle: place.subtitle,
                systemImage: place.searchSystemImage,
                tint: place.searchIconTint
            )
        }
        .buttonStyle(.plain)
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
            isSearching = false
            return
        }

        // Clear stale results immediately so a previous query is never shown
        // as if it matched the current text. The short debounce keeps the
        // search services from being hit for every keystroke.
        results = []
        isSearching = true
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        async let stopMatches = gtfsService.searchStops(query: current)
        async let placeMatches = placeSearchService.searchPlaces(
            query: current,
            near: viewModel.currentLocation?.location
        )
        let stops = await stopMatches
        guard !Task.isCancelled else { return }
        results = mergedResults(stops: stops, places: [])

        let places = await placeMatches
        guard !Task.isCancelled else { return }
        results = mergedResults(stops: stops, places: places)
        isSearching = false
    }

    private func mergedResults(stops: [Stop], places: [RoutePlace]) -> [RoutePlace] {
        var seenIDs = Set<String>()
        let stopResults = stops
            .deduplicatedByExactName()
            .prefix(30)
            .map { RoutePlace(stop: $0, source: .search) }
        let placeResults = Array(places.prefix(10))
        return (stopResults + placeResults)
            .filter { seenIDs.insert($0.id).inserted }
            .prefix(40)
            .map { $0 }
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

private struct RoutePlaceRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let subtitle, !subtitle.isEmpty else { return title }
        return "\(title), \(subtitle)"
    }
}
