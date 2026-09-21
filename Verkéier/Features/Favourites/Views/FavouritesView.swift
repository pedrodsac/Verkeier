import SwiftUI

struct FavouritesView: View {
    let viewModel: FavouritesPresentationModel
    let actions: FavouritesActions

    @State private var editingFavourite: FavouriteStopPresentationModel?
    @State private var lastEditedFavouriteID: String?
    @AccessibilityFocusState private var focusedFavouriteID: String?

    var body: some View {
        Group {
            if visibleStops.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "star")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button("Find a stop", action: actions.findStop)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable { await refreshAll() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Refresh favourites", systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.liveDeparturesAvailable || viewModel.isRefreshing || visibleStops.isEmpty)
            }
        }
        .sheet(item: $editingFavourite, onDismiss: restoreEditedFavouriteFocus) { favourite in
            FavouriteLabelsEditor(
                favourite: favourite,
                availableLabels: viewModel.availableLabels,
                save: { labels in
                    actions.updateLabels(favourite.stop.id, labels)
                }
            )
        }
    }

    private var visibleStops: [FavouriteStopPresentationModel] {
        viewModel.stops
    }

    private let emptyTitle: LocalizedStringKey = "No favourites"

    private let emptyDescription: LocalizedStringKey = "Save a stop from its detail view."

    private var sections: [FavouriteLabelSection] {
        viewModel.labelSections(for: visibleStops)
    }

    private func sectionView(_ section: FavouriteLabelSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if section.title != String(localized: "Saved Stops") {
                Text(section.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            LazyVStack(spacing: 8) {
                ForEach(section.stops) { favourite in
                    Button {
                        actions.openStop(favourite.stop)
                    } label: {
                        StopRow(
                            stop: favourite.stop,
                            markerColor: favourite.stop.modes.primaryMode.tint
                        )
                        .padding(8)
                        .cardSurface(radius: Radius.row)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityFocused($focusedFavouriteID, equals: favourite.id)
                    .accessibilityHint("Opens departures for this stop")
                    .accessibilityAction(named: "Plan to \(favourite.stop.displayName)") {
                        actions.planTo(favourite.stop)
                    }
                    .accessibilityAction(named: "Plan from \(favourite.stop.displayName)") {
                        actions.planFrom(favourite.stop)
                    }
                    .accessibilityAction(named: "Refresh departures for \(favourite.stop.displayName)") {
                        Task { await actions.refreshStop(favourite.stop) }
                    }
                    .accessibilityAction(named: "Remove \(favourite.stop.displayName) from favourites") {
                        actions.removeFavourite(favourite.stop.id)
                    }
                    .contextMenu {
                        favouriteContextMenu(for: favourite)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAll() async {
        guard viewModel.liveDeparturesAvailable else { return }
        await actions.refreshAll()
        UIAccessibility.post(notification: .announcement, argument: "Favourites refreshed")
    }

    private func restoreEditedFavouriteFocus() {
        guard let lastEditedFavouriteID else { return }
        Task { @MainActor in
            focusedFavouriteID = lastEditedFavouriteID
            self.lastEditedFavouriteID = nil
        }
    }

    @ViewBuilder
    private func favouriteContextMenu(for favourite: FavouriteStopPresentationModel) -> some View {
        let stop = favourite.stop
        Button {
            actions.openStop(stop)
        } label: {
            Label("Open departures", systemImage: "clock")
        }
        Button {
            actions.planTo(stop)
        } label: {
            Label("Plan to this stop", systemImage: "arrow.right.circle")
        }
        Button {
            actions.planFrom(stop)
        } label: {
            Label("Plan from this stop", systemImage: "arrow.left.circle")
        }
        Button {
            Task { await actions.refreshStop(stop) }
        } label: {
            Label("Refresh departures", systemImage: "arrow.clockwise")
        }
        Button {
            lastEditedFavouriteID = favourite.id
            editingFavourite = favourite
        } label: {
            Label("Edit labels", systemImage: "tag")
        }
        Divider()
        Button(role: .destructive) {
            actions.removeFavourite(stop.id)
        } label: {
            Label("Remove favourite", systemImage: "star.slash")
        }
    }

}

struct FavouriteLabelsEditor: View {
    let favourite: FavouriteStopPresentationModel
    let availableLabels: [String]
    let save: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var labels: [String]
    @State private var draft = ""

    init(
        favourite: FavouriteStopPresentationModel,
        availableLabels: [String],
        save: @escaping ([String]) -> Void
    ) {
        self.favourite = favourite
        self.availableLabels = availableLabels
        self.save = save
        _labels = State(initialValue: favourite.labels)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Labels") {
                    if labels.isEmpty {
                        Text("No labels assigned")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(labels, id: \.self) { label in
                            HStack {
                                Text(label)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    labels.removeAll { $0 == label }
                                }
                            }
                        }
                    }
                }

                Section("Add label") {
                    HStack {
                        TextField("Label", text: $draft)
                            .onSubmit(addDraft)
                        Button("Add", action: addDraft)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                let suggestions = availableLabels.filter { candidate in
                    !labels.contains { $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                }
                if !suggestions.isEmpty {
                    Section("Existing labels") {
                        ForEach(suggestions, id: \.self) { label in
                            Button(label) { labels.append(label) }
                        }
                    }
                }
            }
            .navigationTitle("Edit Labels")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save(labels)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !labels.contains(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else {
            return
        }
        labels.append(trimmed)
        draft = ""
    }
}
