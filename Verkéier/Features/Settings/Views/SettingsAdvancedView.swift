import SwiftUI

struct SettingsAdvancedView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void

    private var configuration: AppConfiguration { viewModel.configuration }

    var body: some View {
        List {
            Section("Data Status") {
                AdvancedReadinessCard(
                    title: viewModel.readiness.summaryTitle,
                    message: viewModel.readiness.summaryMessage
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                ForEach(viewModel.readiness.items) { item in
                    AdvancedFactRow(
                        iconName: item.iconName,
                        title: "\(item.title): \(item.status)",
                        message: item.detail
                    )
                }
            }

            Section("API") {
                AdvancedDiagnosticRow(label: "ATP mode", value: atpMode)
                AdvancedDiagnosticRow(
                    label: "ATP endpoint",
                    value: configuration.apiProxyURL?.host() ?? "Unavailable"
                )
                AdvancedDiagnosticRow(label: "Transit data cache", value: gtfsSummary)
                AdvancedDiagnosticRow(
                    label: "AVL feed",
                    value: configuration.avlMessagesURL.host() ?? "Configured"
                )
                AdvancedDiagnosticRow(label: "Routing", value: "MapKit + Apple Maps")
            }

            Section("Transit data details") {
                AdvancedDiagnosticRow(
                    label: "Dataset",
                    value: "Luxembourg public transport data"
                )
                AdvancedDiagnosticRow(label: "Source file", value: currentGTFSResource)
                AdvancedDiagnosticRow(
                    label: "Downloaded",
                    value: formatted(viewModel.gtfsUpdateSnapshot.metadata?.downloadedAt)
                )
                AdvancedDiagnosticRow(
                    label: "Last checked",
                    value: formatted(viewModel.gtfsUpdateSnapshot.lastMetadataCheckAt)
                )
                AdvancedDiagnosticRow(
                    label: "Last modified",
                    value: formatted(viewModel.gtfsUpdateSnapshot.metadata?.lastModified)
                )
                AdvancedDiagnosticRow(
                    label: "Checksum",
                    value: viewModel.gtfsUpdateSnapshot.metadata?.checksum ?? "Unavailable"
                )
                AdvancedDiagnosticRow(label: "Status", value: gtfsStatusText)

                if let lastFailureMessage = viewModel.gtfsUpdateSnapshot.lastFailureMessage {
                    AdvancedFactRow(
                        iconName: "exclamationmark.triangle.fill",
                        title: "Last update failed",
                        message: lastFailureMessage
                    )
                }

                Button(action: checkGTFSUpdate) {
                    Label(
                        viewModel.isCheckingGTFSUpdate ? "Checking…" : "Check for data update",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(viewModel.isCheckingGTFSUpdate)
                .accessibilityHint("Checks data.public.lu for a newer public-transport data version")
            }

            Section("Support") {
                AdvancedDiagnosticRow(label: "Version", value: appVersion)
                ShareLink(item: viewModel.supportBundleText) {
                    Label("Export support bundle", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            #if DEBUG
            Section("Debug Data Mode") {
                Picker(
                    "Debug data mode",
                    selection: Binding(
                        get: { viewModel.debugDataMode },
                        set: setDebugDataMode
                    )
                ) {
                    ForEach(DebugTransitDataMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Text(viewModel.debugDataMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .toolbarTitleDisplayMode(.inline)
    }

    // MARK: - Computed

    private var appVersion: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
        if viewModel.isCheckingGTFSUpdate { return "Checking" }
        switch viewModel.gtfsUpdateSnapshot.status {
        case .idle: return "Idle"
        case .checking: return "Checking"
        case .upToDate: return "Up to date"
        case .updated: return "Updated"
        case .failed: return "Update failed"
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Shared helper components

struct AdvancedReadinessCard: View {
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

struct AdvancedFactRow: View {
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

struct AdvancedDiagnosticRow: View {
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
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
