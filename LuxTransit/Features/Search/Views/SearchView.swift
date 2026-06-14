import SwiftUI

struct SearchView: View {
    @Binding var query: String
    let viewModel: SearchPresentationModel
    let updateSearch: () -> Void
    let selectStop: (Stop) -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NearbySearchSuggestions(
                    stops: viewModel.nearbySuggestions,
                    isLoading: viewModel.isLoadingNearbySuggestions,
                    selectStop: selectStop
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if viewModel.results.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try another stop name.")
                )
                .transition(.opacity)
            } else {
                resultsList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.24), value: query.isEmpty)
        .animation(.snappy(duration: 0.24), value: viewModel.results.count)
        .onAppear {
            isSearchFocused = true
            updateSearch()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search stops", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onSubmit(updateSearch)
                .accessibilityLabel("Stop search")

            if !query.isEmpty {
                Button {
                    query = ""
                    updateSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 0.5)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.results) { stop in
                    StopListRow(
                        stop: stop,
                        markerColor: .blue,
                        accessorySystemName: "arrow.up.left.and.arrow.down.right"
                    ) {
                        selectStop(stop)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

private struct NearbySearchSuggestions: View {
    let stops: [Stop]
    let isLoading: Bool
    let selectStop: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby Suggestions")
                .font(.headline.weight(.semibold))

            if isLoading && stops.isEmpty {
                ProgressView("Finding nearby stops")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if stops.isEmpty {
                ContentUnavailableView(
                    "Search stops",
                    systemImage: "tram",
                    description: Text("Start typing to find stops from local GTFS data.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(stops.prefix(5)) { stop in
                            StopListRow(stop: stop, markerColor: .teal) {
                                selectStop(stop)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

#Preview {
    SearchView(
        query: .constant(""),
        viewModel: SearchPresentationModel(
            results: [],
            nearbySuggestions: [],
            isLoadingNearbySuggestions: false
        ),
        updateSearch: {},
        selectStop: { _ in }
    )
}
