import SwiftData
import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                AboutAppHeader()
            }

            Section("Schedules") {
                AboutSourceRow(
                    iconName: "bus.fill",
                    title: "Bus schedules",
                    source: "Administration des transports publics · data.public.lu GTFS"
                )
                AboutSourceRow(
                    iconName: "tram.fill",
                    title: "Tram schedules",
                    source: "Administration des transports publics · data.public.lu GTFS"
                )
                AboutSourceRow(
                    iconName: "train.side.front.car",
                    title: "Train schedules",
                    source: "Administration des transports publics · data.public.lu GTFS"
                )
            }

            Section("Live information") {
                AboutSourceRow(
                    iconName: "antenna.radiowaves.left.and.right",
                    title: "Live departures",
                    source: "mobiliteit.lu OpenAPI"
                )
                AboutSourceRow(
                    iconName: "exclamationmark.triangle.fill",
                    title: "AVL service warnings",
                    source: "Ville de Luxembourg · AVL Autobus"
                )
                AboutSourceRow(
                    iconName: "bicycle",
                    title: "vel'OH! bike share",
                    source: "JCDecaux"
                )
            }

            Section("Maps") {
                AboutSourceRow(
                    iconName: "map.fill",
                    title: "Maps and walking routes",
                    source: "Apple Maps / MapKit"
                )
            }

            Section("Privacy") {
                AboutFactRow(
                    iconName: "location.fill",
                    title: "Location",
                    message:
                    "Location is used on device for nearby stops and route planning. You can use the app with mocked or searched stops if location is unavailable."
                )
                AboutFactRow(
                    iconName: "star.fill",
                    title: "Favourites",
                    message:
                    "Favourite stops are stored locally with SwiftData and mirrored to Shortcuts for App Intent suggestions."
                )
                AboutFactRow(
                    iconName: "internaldrive.fill",
                    title: "Data on your device",
                    message:
                    "Recent places, trips, and commute presets are stored locally on your device."
                )
                AboutFactRow(
                    iconName: "person.crop.circle.badge.xmark",
                    title: "No account or ads",
                    message: "Verkéier does not require an account or use advertising."
                )
            }

            Section("Your data") {
                Button("Delete all local data", role: .destructive) {
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
                    Text("This removes favourites, recent stops, trips, and commute presets from this device.")
                }
            }

            Section("Legal") {
                Text("Verkéier is an independent app and is not affiliated with or endorsed by Luxembourg public transport operators.")
                    .font(.footnote)
                Text("Schedules, live departures, bike-share availability, and service warnings are provided by their respective data publishers and may be incomplete or delayed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("More") {
                NavigationLink {
                    SettingsOpenSourceView()
                } label: {
                    Label("Open-source libraries", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .listStyle(.insetGrouped)
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

private struct AboutAppHeader: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Verkéier")
                    .font(.title3.weight(.semibold))
                Text("Public transport for Luxembourg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(versionText)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct AboutSourceRow: View {
    let iconName: String
    let title: String
    let source: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(source)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AboutFactRow: View {
    let iconName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        SettingsAboutView()
    }
}
