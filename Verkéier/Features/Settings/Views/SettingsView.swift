import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    let viewModel: SettingsPresentationModel
    let checkGTFSUpdate: () -> Void
    let setDebugDataMode: (DebugTransitDataMode) -> Void

    @Environment(AppPreferences.self) private var preferences
    @State private var searchText = ""

    /// True when the section's keywords match the current search (or no search).
    private func matches(_ keywords: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return query.isEmpty || keywords.lowercased().contains(query)
    }

    var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            List {
                if matches("appearance theme dark light system") {
                    Section("Appearance") {
                        Picker("Theme", selection: $prefs.appearance) {
                            ForEach(AppearancePreference.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }

                if matches("units distance km miles kilometres") {
                    Section("Units") {
                        Picker("Distance", selection: $prefs.distanceUnit) {
                            ForEach(DistanceUnitPreference.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                    }
                }

                if matches("route planner defaults sort mode transfers accessible step-free") {
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
                }

                if matches("offline mode data live realtime schedule gtfs transfers") {
                    Section {
                        Toggle("Offline mode", isOn: $prefs.offlineMode)
                    } header: {
                        Text("Data")
                    } footer: {
                        Text("Plan journeys from the static schedule only, without live "
                            + "departures, delays, or cancellations. Adds a 15-minute "
                            + "minimum between transfers as a safety buffer.")
                    }
                }

                if matches("reminders lead time departure notification") {
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
                }

                if matches("permissions notifications location privacy access") {
                    SettingsPermissionsSection()
                }

                if matches("advanced about legal diagnostics gtfs data status export") {
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
            }
            .listStyle(.insetGrouped)
            // Give every settings glyph subtle layered depth without per-row changes.
            .symbolRenderingMode(.hierarchical)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search settings"
            )
        }
    }
}

/// A settings section showing notification and location permission status with a
/// one-tap jump to the iOS Settings app.
private struct SettingsPermissionsSection: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus = "Checking…"

    var body: some View {
        Section("Permissions") {
            LabeledContent("Notifications", value: notificationStatus)
            LabeledContent("Location", value: locationStatusText)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: "Allowed"
            case .denied: "Denied"
            case .notDetermined: "Not requested"
            @unknown default: "Unknown"
            }
        }
    }

    private var locationStatusText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "Allowed"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
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
                summaryMessage: "This screen shows whether Verkéier is using live, downloaded, bundled, or fallback data.",
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
