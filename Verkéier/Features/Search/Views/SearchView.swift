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

struct SearchView: View {
    @Binding var query: String
    let viewModel: SearchPresentationModel
    let actions: SearchActions

    var body: some View {
        SearchResultsContent(
            query: $query,
            viewModel: viewModel,
            actions: actions
        )
    }
}

struct SearchResultsContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var query: String
    let viewModel: SearchPresentationModel
    let actions: SearchActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Group {
                    if viewModel.recentStops.isEmpty {
                        NearbySearchSuggestions(
                            stops: viewModel.nearbySuggestions,
                            isLoading: viewModel.isLoadingNearbySuggestions,
                            referenceLocation: viewModel.referenceLocation,
                        )
                    } else {
                        RecentSearchStops(
                            stops: viewModel.recentStops,
                            referenceLocation: viewModel.referenceLocation
                        )
                    }
                }
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
        .animation(Animation.respectingReduceMotion(.snappy(duration: 0.24), reduceMotion), value: query.isEmpty)
        .animation(
            Animation.respectingReduceMotion(.snappy(duration: 0.24), reduceMotion),
            value: viewModel.results.count
        )
        .onAppear {
            actions.updateSearch()
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.results) { stop in
                    StopListRow(
                        stop: stop,
                        markerColor: .blue,
                        accessorySystemName: "chevron.right",
                        navigationValue: .stopDetail(stop)
                    )
                }
            }
            .padding(.vertical, 75)
			.padding(.horizontal, 16)
        }
    }
}

private struct RecentSearchStops: View {
    let stops: [Stop]
    let referenceLocation: CLLocation?

    var body: some View {
		VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVStack(spacing: 10) {
					HStack {
						Text("Recent")
							.font(.headline.weight(.semibold))

						Spacer()
					}
					.padding(.bottom, 2)

                    ForEach(stops.prefix(8)) { stop in
                        StopListRow(
                            stop: stop,
                            markerColor: .blue,
                            accessorySystemName: "chevron.right",
                            referenceLocation: referenceLocation,
                            navigationValue: .stopDetail(stop)
                        )
                    }
                }
                .padding(.vertical, 75)
				.padding(.horizontal, 16)
            }
        }
    }
}

private struct NearbySearchSuggestions: View {
    let stops: [Stop]
    let isLoading: Bool
    let referenceLocation: CLLocation?

    var body: some View {
        VStack(spacing: 12) {
            if isLoading, stops.isEmpty {
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
						HStack {
							Text("Nearby Suggestions")
								.font(.headline.weight(.semibold))

							Spacer()
						}
						.padding(.bottom, 2)

                        ForEach(stops.prefix(5)) { stop in
                            StopListRow(
                                stop: stop,
                                markerColor: .teal,
                                referenceLocation: referenceLocation,
                                navigationValue: .stopDetail(stop)
                            )
                        }
                    }
					.padding(.vertical, 75)
					.padding(.horizontal, 16)
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
            isLoadingNearbySuggestions: false,
            referenceLocation: nil
        ),
        actions: SearchActions()
    )
}
