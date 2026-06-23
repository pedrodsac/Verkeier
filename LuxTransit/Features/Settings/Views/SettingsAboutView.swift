import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section("Attribution") {
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
                    iconName: "person.crop.circle.badge.xmark",
                    title: "No account",
                    message:
                        "LuxTransit does not add accounts, ads, subscriptions, or a backend service."
                )
            }

            Section {
                Text("This app is not an official Luxembourg public transport app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About & Legal")
        .navigationBarTitleDisplayMode(.inline)
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
    SettingsAboutView()
}
