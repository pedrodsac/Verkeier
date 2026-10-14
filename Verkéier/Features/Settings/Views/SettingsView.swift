import SwiftUI

struct SettingsView: View {
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
                Toggle("Avoid tight transfers", isOn: $prefs.avoidTightTransfers)
            }

            Section {
                ForEach(RoutePlannerFilters.selectableModes) { mode in
                    Toggle(
                        isOn: Binding(
                            get: { preferences.includedRouteModes.contains(mode) },
                            set: { included in
                                if included {
                                    preferences.includedRouteModes.insert(mode)
                                } else {
                                    preferences.includedRouteModes.remove(mode)
                                }
                            }
                        )
                    ) {
                        Label {
                            Text(LocalizedStringKey(mode.displayName))
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: mode.symbolName)
                                .foregroundStyle(mode.tint)
                        }
                    }
                }
            } header: {
                Text("Transport in routes")
            } footer: {
                Text("Choose which transport modes route planning can use.")
            }

            Section {
                Toggle(isOn: $prefs.showBusStops) {
                    mapPinLabel("Bus stops", mode: .bus)
                }
                Toggle(isOn: $prefs.showTramStops) {
                    mapPinLabel("Tram stops", mode: .tram)
                }
                Toggle(isOn: $prefs.showTrainStations) {
                    mapPinLabel("Train stations", mode: .train)
                }
                Toggle(isOn: $prefs.showBikeShareStations) {
                    mapPinLabel("Bike share stations", mode: .bicycle)
                }
            } header: {
                Text("Map pins")
            } footer: {
                Text("Choose which stops and stations appear on the map.")
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
    SettingsView()
        .environment(AppPreferences())
}
