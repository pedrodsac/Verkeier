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
                AdvancedDiagnosticRow(
                    label: "AVL feed",
                    value: configuration.avlMessagesURL.host() ?? "Configured"
                )
                AdvancedDiagnosticRow(label: "Routing", value: "MapKit + Apple Maps")
            }

            Section("Transit data details") {
                AdvancedDiagnosticRow(label: "GTFS schedules", value: "Disconnected")
                AdvancedDiagnosticRow(label: "ATP live data", value: "Disconnected")
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
