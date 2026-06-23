import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $prefs.appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section("Units") {
                    Picker("Distance", selection: $prefs.distanceUnit) {
                        ForEach(DistanceUnitPreference.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                }

                Section("Route Planner Defaults") {
                    Picker("Sort by", selection: $prefs.defaultRouteSort) {
                        ForEach(RoutePlannerSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Preferred mode", selection: $prefs.defaultModePreference) {
                        ForEach(RoutePlannerModePreference.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("Avoid tight transfers", isOn: $prefs.avoidTightTransfers)
                    Toggle("Prefer step-free routes", isOn: $prefs.preferAccessible)
                }

                Section("Reminders") {
                    Picker(
                        "Default lead time",
                        selection: $prefs.defaultReminderLeadTimeMinutes
                    ) {
                        ForEach(AppPreferences.reminderLeadTimeOptions, id: \.self) { minutes in
                            Text("\(minutes) min before").tag(minutes)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsAdvancedView(
                            viewModel: viewModel,
                            checkGTFSUpdate: checkGTFSUpdate,
                            setDebugDataMode: setDebugDataMode
                        )
                    } label: {
                        Label("Advanced", systemImage: "gearshape.2")
                    }

                    NavigationLink {
                        SettingsAboutView()
                    } label: {
                        Label("About & Legal", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
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
    .environment(AppPreferences())
}
