import SwiftData
import SwiftUI

struct FavouritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) private var favourites: [PersistedFavouriteStop]
    let selectStop: (Stop) -> Void

    @State private var editingStop: PersistedFavouriteStop?
    @State private var labelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if favourites.isEmpty {
                ContentUnavailableView(
                    "No favourites",
                    systemImage: "star",
                    description: Text("Save a stop from its detail view.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections, id: \.title) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Edit Label", isPresented: isEditing, presenting: editingStop) { stop in
            TextField("Label (e.g. Home, Work)", text: $labelDraft)
            Button("Save") { saveLabel(for: stop) }
            if stop.label != nil {
                Button("Remove Label", role: .destructive) { setLabel(nil, for: stop) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { stop in
            Text(stop.name)
        }
    }

    private func sectionView(_ section: LabelSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isGrouped {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(section.stops) { entity in
                StopListRow(stop: entity.stop, markerColor: .yellow) {
                    selectStop(entity.stop)
                }
                .contextMenu {
                    Button {
                        beginEditing(entity)
                    } label: {
                        Label("Edit Label", systemImage: "tag")
                    }
                }
            }
        }
    }

    /// True once any favourite carries a label, which switches the flat list into
    /// labelled sections (with unlabelled stops collected under "Saved Stops").
    private var isGrouped: Bool {
        favourites.contains { ($0.label?.isEmpty == false) }
    }

    private var sections: [LabelSection] {
        guard isGrouped else {
            return [LabelSection(title: "Saved Stops", stops: favourites)]
        }

        let groups = Dictionary(grouping: favourites) { stop -> String in
            stop.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        }

        var result = groups
            .filter { !$0.key.isEmpty }
            .map { LabelSection(title: $0.key, stops: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if let unlabelled = groups[""], !unlabelled.isEmpty {
            result.append(LabelSection(title: "Saved Stops", stops: unlabelled))
        }
        return result
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editingStop != nil }, set: { if !$0 { editingStop = nil } })
    }

    private func beginEditing(_ stop: PersistedFavouriteStop) {
        labelDraft = stop.label ?? ""
        editingStop = stop
    }

    private func saveLabel(for stop: PersistedFavouriteStop) {
        setLabel(labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, for: stop)
    }

    private func setLabel(_ label: String?, for stop: PersistedFavouriteStop) {
        stop.label = label
        try? modelContext.save()
    }

    private struct LabelSection {
        let title: String
        let stops: [PersistedFavouriteStop]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    FavouritesView(selectStop: { _ in })
        .modelContainer(for: PersistedFavouriteStop.self, inMemory: true)
        .environment(AppPreferences())
}
