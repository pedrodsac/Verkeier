import SwiftData
import SwiftUI

/// Searches for a stop to put behind an existing favourite, keeping the
/// favourite's name, look and position.
struct FavouriteStopPickerScreen: View {
    /// The stop the favourite currently points at.
    let favouriteStopID: String

    @Environment(FavouritesModel.self) private var favourites
    @Environment(SearchModel.self) private var search
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.liveTransitService) private var liveTransitService

    @State private var query = ""
    @State private var showsReplacementFailure = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                let recents = search.distinctRecentStops
                if !recents.isEmpty {
                    Section("Recents") {
                        ForEach(recents) { stop in
                            stopButton(stop)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(favourites.replacementSearchResults) { stop in
                        stopButton(stop)
                    }
                }
            }
        }
        .overlay {
            if !trimmedQuery.isEmpty, favourites.replacementSearchResults.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
        .navigationTitle("Change Stop")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search for a stop"
        )
        .task(id: query) {
            // Wait for typing to pause before searching.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await favourites.searchReplacementStops(matching: query, using: gtfsService)
        }
        .onDisappear {
            favourites.replacementSearchResults = []
        }
        .alert("Stop Not Changed", isPresented: $showsReplacementFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That stop is already one of your favourites.")
        }
    }

    private func stopButton(_ stop: Stop) -> some View {
        let isCurrent = stop.id == favouriteStopID
        let isOtherFavourite = !isCurrent && favourites.favouriteStopIDs.contains(stop.id)
        return Button {
            choose(stop)
        } label: {
            HStack {
                StopRow(stop: stop)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                } else if isOtherFavourite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(isOtherFavourite)
        .accessibilityValue(isCurrent ? "Current stop" : isOtherFavourite ? "Already a favourite" : "")
    }

    private func choose(_ stop: Stop) {
        guard stop.id != favouriteStopID else {
            dismiss()
            return
        }
        guard favourites.replaceStop(ofFavouriteWithStopID: favouriteStopID, with: stop, in: modelContext) else {
            showsReplacementFailure = true
            return
        }
        Task {
            await favourites.refreshFavouriteDeparture(
                stop: stop,
                using: liveTransitService,
                gtfsService: gtfsService
            )
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        FavouriteStopPickerScreen(favouriteStopID: "preview")
    }
    .previewEnvironment()
    .modelContainer(for: PersistedFavouriteStop.self, inMemory: true)
}
