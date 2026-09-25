import SwiftData
import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirm = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("About") {
                LabeledContent("App", value: "Verkéier")
                LabeledContent("Version", value: versionText)
            }

            Section("Data sources") {
                LabeledContent("Schedules", value: "ATP · data.public.lu")
                LabeledContent("Live departures", value: "mobiliteit.lu")
                LabeledContent("Service alerts", value: "Ville de Luxembourg · AVL")
                LabeledContent("Bike share", value: "vel'OH! · JCDecaux")
                LabeledContent("Maps", value: "Apple Maps")
                Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                    HStack {
                        Text("Walking routes")
                        Spacer()
                        Text("© OpenStreetMap contributors · ODbL")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section("Network maps") {
                ForEach(PublicTransportMapLink.all) { map in
                    Link(destination: map.url) {
                        HStack {
                            Text(map.language)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section("Privacy") {
                Text("Location is used on device. Saved places and trips stay on this device. No account or ads.")
                    .foregroundStyle(.secondary)
                NavigationLink {
                    SettingsOpenSourceView()
                } label: {
                    Text("Open-source libraries")
                }
            }

            Section("Legal") {
                Text("Verkéier is independent and not affiliated with Luxembourg public transport operators.")
                    .foregroundStyle(.secondary)
                Text("Information may be incomplete or delayed.")
                    .foregroundStyle(.secondary)
            }

            Section("Your data") {
                Button("Delete local data", role: .destructive) {
                    showDeleteConfirm = true
                }
                .confirmationDialog(
                    "Delete local data?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete everything", role: .destructive) {
                        deleteAllLocalData()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes favourites, recent stops, trips, and commute presets from this device.")
                }
            }
        }
        .navigationTitle("About & Legal")
        .toolbarTitleDisplayMode(.inline)
    }

    private func deleteAllLocalData() {
        try? modelContext.delete(model: PersistedFavouriteStop.self)
        try? modelContext.save()
        RoutePlannerStore.shared.clearAll()
        SharedTransitDataStore.saveTrackedReminder(nil)
    }
}

/// A language-specific map published by mobiliteit.lu.
struct PublicTransportMapLink: Identifiable, Hashable, Sendable {
    let id: String
    let language: String
    let url: URL

    static let all: [Self] = [
        Self(
            id: "english",
            language: "English",
            url: URL(string: "https://www.mobiliteit.lu/en/maps/")!
        ),
        Self(
            id: "french",
            language: "Français",
            url: URL(string: "https://www.mobiliteit.lu/fr/plans-detailles/")!
        ),
        Self(
            id: "german",
            language: "Deutsch",
            url: URL(string: "https://www.mobiliteit.lu/de/ubersichtsplane/")!
        )
    ]
}

#Preview {
    NavigationStack {
        SettingsAboutView()
    }
}
