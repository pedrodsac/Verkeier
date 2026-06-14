import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let close: () -> Void

    private var configuration: AppConfiguration {
        viewModel.configuration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Button(action: close) {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close settings")

                    Text("Settings")
                        .font(.title2.weight(.semibold))

                    Spacer(minLength: 0)
                }

                SettingsSection(title: "Attribution") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transport data:")
                            .font(.subheadline.weight(.semibold))
                        Text("Administration des transports publics - mobiliteit.lu OpenAPI")
                        Text(
                            "Administration des transports publics - GTFS public transport schedules and stops"
                        )
                        Text("Ville de Luxembourg - AVL Autobus")

                        Text("Maps:")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
                        Text("Apple Maps / MapKit")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                SettingsSection(title: "Privacy") {
                    SettingsFactRow(
                        iconName: "location.fill",
                        title: "Location",
                        message:
                            "Location is used on device for nearby stops and route planning. You can use the app with mocked or searched stops if location is unavailable."
                    )
                    SettingsFactRow(
                        iconName: "star.fill",
                        title: "Favourites",
                        message:
                            "Favourite stops are stored locally with SwiftData and mirrored to Shortcuts for App Intent suggestions."
                    )
                    SettingsFactRow(
                        iconName: "person.crop.circle.badge.xmark",
                        title: "No account",
                        message:
                            "LuxTransit does not add accounts, ads, subscriptions, or a backend service."
                    )
                }

                SettingsSection(title: "API Diagnostics") {
                    DiagnosticRow(
                        label: "ATP OpenAPI",
                        value: configuration.hasATPAccessId ? "Configured" : "Mocked")
                    DiagnosticRow(label: "GTFS", value: gtfsSummary)
                    DiagnosticRow(
                        label: "AVL", value: configuration.avlMessagesURL.host() ?? "Configured")
                    DiagnosticRow(label: "Routing", value: "MapKit with Apple Maps handoff")
                }

                SettingsSection(title: "Data Sources") {
                    DiagnosticRow(label: "GTFS dataset", value: "Luxembourg public transport GTFS")
                    DiagnosticRow(label: "Current resource", value: currentGTFSResource)
                    DiagnosticRow(
                        label: "Downloaded",
                        value: formatted(viewModel.gtfsUpdateSnapshot.metadata?.downloadedAt))
                    DiagnosticRow(
                        label: "Last checked",
                        value: formatted(viewModel.gtfsUpdateSnapshot.lastMetadataCheckAt))
                    DiagnosticRow(
                        label: "Checksum",
                        value: viewModel.gtfsUpdateSnapshot.metadata?.checksum ?? "Unavailable")
                    DiagnosticRow(label: "Status", value: gtfsStatusText)

                    Button(action: checkGTFSUpdate) {
                        Label(
                            viewModel.isCheckingGTFSUpdate
                                ? "Checking..." : "Check for GTFS update",
                            systemImage: "arrow.clockwise"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCheckingGTFSUpdate)
                    .accessibilityHint("Checks data.public.lu for a newer GTFS feed")
                }

                SettingsSection(title: "Support") {
                    DiagnosticRow(label: "Version", value: appVersion)
                    Text("This app is not an official Luxembourg public transport app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 72)
        }
    }

    private var appVersion: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var gtfsSummary: String {
        viewModel.gtfsUpdateSnapshot.metadata == nil ? "No GTFS data" : "Cached GTFS"
    }

    private var currentGTFSResource: String {
        viewModel.gtfsUpdateSnapshot.metadata?.title ?? "Not downloaded"
    }

    private var gtfsStatusText: String {
        if viewModel.isCheckingGTFSUpdate {
            return "Checking"
        }

        switch viewModel.gtfsUpdateSnapshot.status {
        case .idle:
            return "Idle"
        case .checking:
            return "Checking"
        case .upToDate:
            return "Up to date"
        case .updated:
            return "Updated"
        case .failed:
            return "Update failed"
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                .background.opacity(0.76),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.separator.opacity(0.20), lineWidth: 0.7)
            }
        }
    }
}

private struct SettingsFactRow: View {
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

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SettingsView(
        viewModel: SettingsPresentationModel(
            configuration: .current,
            gtfsUpdateSnapshot: .empty,
            isCheckingGTFSUpdate: false
        ),
        checkGTFSUpdate: {},
        close: {}
    )
}
