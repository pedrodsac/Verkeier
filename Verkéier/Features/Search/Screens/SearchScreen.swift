import SwiftUI

/// Stop search results, or recent and nearby stops before the rider types.
struct SearchScreen: View {
    @Environment(SearchModel.self) private var search
    @Environment(MapModel.self) private var map
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if search.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Group {
                    if search.distinctRecentStops.isEmpty {
                        NearbySearchSuggestions(
                            stops: map.distinctNearbyStops,
                            isLoading: map.isLoadingNearbyStops
                        )
                    } else {
                        RecentSearchStops(stops: search.distinctRecentStops)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if search.searchResults.isEmpty {
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
        .animation(
            Animation.respectingReduceMotion(.snappy(duration: 0.24), reduceMotion),
            value: search.searchQuery.isEmpty
        )
        .animation(
            Animation.respectingReduceMotion(.snappy(duration: 0.24), reduceMotion),
            value: search.searchResults.count
        )
        .onAppear {
            Task { await search.searchStops(using: gtfsService) }
        }
    }

    private var resultsList: some View {
        nativeStopList {
            Section {
                ForEach(search.searchResults) { stop in
                    NavigationLink(value: SheetRoute.stopDetail(stop)) {
                        StopRow(stop: stop)
                    }
                }
            }
        }
    }

    private func nativeStopList<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 75, for: .scrollContent)
    }
}

private struct RecentSearchStops: View {
    let stops: [Stop]

    var body: some View {
        List {
            Section("Recent Stops") {
                ForEach(stops.prefix(8)) { stop in
                    NavigationLink(value: SheetRoute.stopDetail(stop)) {
                        StopRow(stop: stop)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 75, for: .scrollContent)
    }
}

private struct NearbySearchSuggestions: View {
    let stops: [Stop]
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if isLoading, stops.isEmpty {
                ProgressView("Finding nearby stops")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if stops.isEmpty {
                ContentUnavailableView(
                    "Search stops",
                    systemImage: "tram",
                    description: Text("Start typing to search places and addresses.")
                )
            } else {
                List {
                    Section("Nearby Suggestions") {
                        ForEach(stops.prefix(6)) { stop in
                            NavigationLink(value: SheetRoute.stopDetail(stop)) {
                                StopRow(stop: stop, markerColor: .teal)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.top, 75, for: .scrollContent)
            }
        }
    }
}
