import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void

    private var configuration: AppConfiguration {
        viewModel.configuration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Data Readiness") {
                    ReadinessSummaryCard(
                        title: viewModel.readiness.summaryTitle,
                        message: viewModel.readiness.summaryMessage
                    )

                    ForEach(viewModel.readiness.items) { item in
                        SettingsFactRow(
                            iconName: item.iconName,
                            title: "\(item.title): \(item.status)",
                            message: item.detail
                        )
                    }
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
                    DiagnosticRow(label: "ATP mode", value: atpMode)
                    DiagnosticRow(
                        label: "ATP endpoint",
                        value: configuration.apiBaseURL.host() ?? "Configured"
                    )
                    DiagnosticRow(label: "GTFS cache", value: gtfsSummary)
                    DiagnosticRow(
                        label: "AVL feed",
                        value: configuration.avlMessagesURL.host() ?? "Configured"
                    )
                    DiagnosticRow(label: "Routing", value: "MapKit and Apple Maps handoff")
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
                        label: "Last modified",
                        value: formatted(viewModel.gtfsUpdateSnapshot.metadata?.lastModified)
                    )
                    DiagnosticRow(
                        label: "Checksum",
                        value: viewModel.gtfsUpdateSnapshot.metadata?.checksum ?? "Unavailable")
                    DiagnosticRow(label: "Status", value: gtfsStatusText)
                    if let lastFailureMessage = viewModel.gtfsUpdateSnapshot.lastFailureMessage {
                        SettingsFactRow(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Last update failed",
                            message: lastFailureMessage
                        )
                    }

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
                    ShareLink(item: viewModel.supportBundleText) {
                        Label("Export support bundle", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    Text("This app is not an official Luxembourg public transport app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                    SettingsSection(title: "Debug Data Mode") {
                        DebugDataModePicker(
                            selection: viewModel.debugDataMode,
                            setDebugDataMode: setDebugDataMode
                        )
                    }
                #endif
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
        viewModel.gtfsUpdateSnapshot.metadata == nil ? "Unavailable" : "Cached locally"
    }

    private var atpMode: String {
        configuration.hasATPAccessId ? "Live API configured" : "Mock fallback"
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

#if DEBUG
    private struct DebugDataModePicker: View {
        let selection: DebugTransitDataMode
        let setDebugDataMode: (DebugTransitDataMode) -> Void

        var body: some View {
            Picker(
                "Debug data mode",
                selection: Binding(
                    get: { selection },
                    set: setDebugDataMode
                )
            ) {
                ForEach(DebugTransitDataMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selection.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
#endif

private struct ReadinessSummaryCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            isCheckingGTFSUpdate: false,
            readiness: DataReadinessSnapshot(
                summaryTitle: "Transit data is ready",
                summaryMessage: "This screen shows whether LuxTransit is using live, downloaded, bundled, or fallback data.",
                items: []
            ),
            supportBundleText: "Preview",
            debugDataMode: .normal
        ),
        checkGTFSUpdate: {},
        setDebugDataMode: { _ in }
    )
}
