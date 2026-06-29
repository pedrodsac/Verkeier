import SwiftUI

/// First-launch screen explaining the app's data sources (ATP live departures,
/// GTFS schedules/search, AVL disruptions) and showing current readiness, so the
/// app never silently boots into an empty database.
struct FirstRunOnboardingView: View {
    let readiness: DataReadinessSnapshot
    let onGetStarted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "tram.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("LuxTransit")
                            .font(.largeTitle.weight(.bold))
                        Text("Luxembourg public transport — departures, journeys, and disruptions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        AdvancedFactRow(
                            iconName: "location.fill",
                            title: "Location",
                            message: "Shows nearby stops on the map. The app still works if you decline."
                        )
                        AdvancedFactRow(
                            iconName: "dot.radiowaves.left.and.right",
                            title: "Live departures (ATP)",
                            message: "Real-time departures from mobiliteit.lu. Needs an access key; scheduled times work without it."
                        )
                        AdvancedFactRow(
                            iconName: "tram.fill",
                            title: "Schedules & search (GTFS)",
                            message: "On-device timetables and stop search from data.public.lu. Downloads on first launch and refreshes automatically."
                        )
                        AdvancedFactRow(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Disruptions (AVL)",
                            message: "Service alerts from the Ville de Luxembourg feed."
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(readiness.summaryTitle)
                            .font(.headline)
                        Text(readiness.summaryMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(readiness.items) { item in
                            AdvancedFactRow(
                                iconName: item.iconName,
                                title: "\(item.title) — \(item.status)",
                                message: item.detail
                            )
                        }
                    }
                    .padding(12)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onGetStarted) {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }
}
