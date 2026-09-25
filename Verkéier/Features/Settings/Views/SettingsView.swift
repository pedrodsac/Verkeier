import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences

        List {
            Section("Appearance") {
                Picker("Theme", selection: $prefs.appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Travel") {
                Toggle("Offline schedules", isOn: $prefs.offlineMode)
                Picker("Distance", selection: $prefs.distanceUnit) {
                    ForEach(DistanceUnitPreference.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                Picker("Preferred transport", selection: $prefs.defaultModePreference) {
                    ForEach(RoutePlannerModePreference.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Avoid tight transfers", isOn: $prefs.avoidTightTransfers)
                Toggle("Step-free routes", isOn: $prefs.preferAccessible)
            }

            Section("Map") {
                Toggle(isOn: $prefs.showBikeShareStations) {
                    mapPinLabel("Bike share", mode: .bicycle)
                }
                Toggle(isOn: $prefs.showBusStops) {
                    mapPinLabel("Bus stops", mode: .bus)
                }
                Toggle(isOn: $prefs.showTramStops) {
                    mapPinLabel("Tram stops", mode: .tram)
                }
                Toggle(isOn: $prefs.showTrainStations) {
                    mapPinLabel("Train stations", mode: .train)
                }
            }

            Section("Reminders") {
                Picker("Reminder", selection: $prefs.defaultReminderLeadTimeMinutes) {
                    ForEach(AppPreferences.reminderLeadTimeOptions, id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
            }

            Section {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Label("About & Legal", systemImage: "info.circle")
                }
            }
        }
        .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private func mapPinLabel(_ title: LocalizedStringKey, mode: TransportMode) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: mode.symbolName)
                .foregroundStyle(mode.tint)
        }
    }
}

#Preview {
    SettingsView(
        viewModel: SettingsPresentationModel(
            configuration: .current,
            readiness: DataReadinessSnapshot(
                summaryTitle: "Transit data is ready",
                summaryMessage: "",
                items: []
            ),
            gtfsStatus: .unavailable,
            supportBundleText: "Preview",
            debugDataMode: .normal
        ),
        checkGTFSUpdate: {},
        setDebugDataMode: { _ in }
    )
    .environment(AppPreferences())
}

struct TimetablePreparationProgress: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView()
                .progressViewStyle(.linear)
            Text("Downloading timetable…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing timetable data")
    }
}
