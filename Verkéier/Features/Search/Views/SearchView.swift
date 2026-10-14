import CoreLocation
import SwiftUI
import UIKit

struct StopSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isActive: Bool
    @Binding var focusRequested: Bool
    var placeholder = "Search stops"
    var accessibilityIdentifier = "stop-search"
    var accessibilityLabel = "Stop search"
    let onActivate: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.backgroundImage = UIImage()
        searchBar.backgroundColor = .clear
        searchBar.barTintColor = .clear
        searchBar.placeholder = placeholder
        searchBar.accessibilityIdentifier = accessibilityIdentifier
        searchBar.searchTextField.accessibilityLabel = accessibilityLabel
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        if uiView.showsCancelButton != isActive {
            uiView.setShowsCancelButton(isActive, animated: true)
        }

        if focusRequested, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard self.focusRequested else { return }
                guard !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isActive, uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard !self.isActive else { return }
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: StopSearchBar

        init(_ parent: StopSearchBar) {
            self.parent = parent
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            parent.isActive = true
            parent.onActivate()
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.onCancel()
        }
    }
}

/// Stop search results, or recent and nearby stops before the rider types.
struct SearchResultsContent: View {
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
                    NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
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
                    NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
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
                            NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
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
