import SwiftData
import SwiftUI

/// Lists the saved favourites so the rider can reorder them, change the stop
/// behind one, or remove them.
struct FavouritesManagerSheet: View {
    @Environment(FavouritesModel.self) private var favourites
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: PersistedFavouriteStop.displayOrder) private var savedFavourites: [PersistedFavouriteStop]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(savedFavourites) { favourite in
                        NavigationLink {
                            FavouriteStopPickerScreen(favouriteStopID: favourite.stopId)
                        } label: {
                            row(favourite)
                        }
                        .accessibilityHint("Changes the stop for this favourite")
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("Drag to reorder. Tap a favourite to change its stop.")
                }
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .overlay {
                if savedFavourites.isEmpty {
                    ContentUnavailableView(
                        "No Favourites",
                        systemImage: "star",
                        description: Text("Save a stop from its departures to see it here.")
                    )
                }
            }
        }
    }

    private func row(_ favourite: PersistedFavouriteStop) -> some View {
        let stop = favourite.stop
        return StopRow(
            stop: stop,
            markerColor: favourite.colorHex.map { Color(hex: $0) } ?? stop.modes.primaryMode.tint,
            title: favourite.displayLabel ?? stop.displayName,
            subtitle: stop.fullName,
            iconName: favourite.iconName
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var stopIDs = savedFavourites.map(\.stopId)
        stopIDs.move(fromOffsets: source, toOffset: destination)
        favourites.reorder(stopIDs: stopIDs, in: modelContext)
    }

    private func delete(at offsets: IndexSet) {
        for stopID in offsets.map({ savedFavourites[$0].stopId }) {
            favourites.remove(stopID: stopID, in: modelContext)
        }
    }
}

#Preview {
    FavouritesManagerSheet()
        .previewEnvironment()
        .modelContainer(for: PersistedFavouriteStop.self, inMemory: true)
}
