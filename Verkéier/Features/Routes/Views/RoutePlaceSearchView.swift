import SwiftUI

/// Search destination pushed from a Plan endpoint. The endpoint's current
/// value and the device location stay above the reusable recent places list.
struct RoutePlaceSearchView: View {
    let endpoint: RouteEndpoint
    let viewModel: RoutePresentationModel
    let onSelect: (RoutePlace?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.placeSearchService) private var placeSearchService
    @State private var query = ""
    @State private var results: [RoutePlace] = []
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    currentLocationButton

                    if let selectedPlace,
                       selectedPlace.id != viewModel.currentLocation?.id {
                        placeButton(selectedPlace)
                    }

                    let recents = viewModel.recentPlacesExcludingPinned(for: endpoint)
                    if !recents.isEmpty {
                        Text("Recent")
                            .font(.headline.weight(.semibold))
                            .padding(.top, 10)
                            .padding(.bottom, 2)

                        ForEach(recents) { place in
                            placeButton(place)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 75)
                .padding(.horizontal, 16)
            }
        } else if results.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "mappin.slash",
                description: Text("Try another stop, address, or place name.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { place in
                        placeButton(place)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 75)
                .padding(.horizontal, 16)
            }
        }
    }

    private var currentLocationButton: some View {
        Button(action: selectCurrentLocation) {
            RoutePlaceSearchRow(
                title: "Current Location",
                subtitle: viewModel.currentLocation?.subtitle ?? "Live device location",
                systemImage: "location.fill",
                tint: .blue
            )
        }
        .buttonStyle(.pressable)
        .disabled(endpoint == .destination && viewModel.currentLocation == nil)
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
        .buttonStyle(.pressable)
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

        async let places = placeSearchService.searchPlaces(
            query: current,
            near: viewModel.currentLocation?.location
        )
        let placeResults = await places
        guard !Task.isCancelled else { return }

        var seenIDs = Set<String>()
        results = placeResults.filter { seenIDs.insert($0.id).inserted }
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
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 0.5)
        }
    }
}
