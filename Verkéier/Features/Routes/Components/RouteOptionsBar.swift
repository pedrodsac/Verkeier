import SwiftUI

/// A compact menu for constraints that affect the fastest departure profile.
struct RouteOptionsBar: View {
    let filters: RoutePlannerFilters
    let hasDestination: Bool
    let updateRouteFilters: (RoutePlannerFilters) -> Void
    /// Saves the current origin→destination as a commute preset. The string is an
    /// optional custom label; pass empty to auto-name it "Origin to Destination".
    let saveCurrentCommutePreset: (String) -> Void

    @State private var showingSaveAlert = false
    @State private var presetLabel = ""

    var body: some View {
        optionsMenu
        .alert("Save commute", isPresented: $showingSaveAlert) {
            TextField("Label (e.g. Home → Work)", text: $presetLabel)
            Button("Save") {
                saveCurrentCommutePreset(presetLabel)
                presetLabel = ""
            }
            Button("Cancel", role: .cancel) { presetLabel = "" }
        } message: {
            Text(
                "Name this trip so you can re-plan it in one tap. Use “Home → Work” for time-of-day commute suggestions."
            )
        }
    }

    private var optionsMenu: some View {
		Menu("Route options", systemImage: "slider.horizontal.3") {
            // Mode preference
            Picker(
                "Mode preference",
                selection: Binding(
                    get: { filters.modePreference },
                    set: { updated in apply(\.modePreference, value: updated) }
                )
            ) {
                ForEach(RoutePlannerModePreference.allCases) { option in
                    Label(
                        option.title,
                        systemImage: option.transportMode?.symbolName ?? "circle.grid.2x2"
                    )
                    .tag(option)
                }
            }
            .pickerStyle(.inline)

            Divider()

            // Boolean toggles
            Toggle(
                "Avoid tight transfers",
                isOn: Binding(
                    get: { filters.avoidTightTransfers },
                    set: { updated in apply(\.avoidTightTransfers, value: updated) }
                )
            )

            if hasDestination {
                Divider()
                Button("Save Commute…") { showingSaveAlert = true }
            }
        }
        .accessibilityLabel("Route options")
    }

    // MARK: - Helpers

    private func apply<T>(_ keyPath: WritableKeyPath<RoutePlannerFilters, T>, value: T) {
        var updated = filters
        updated[keyPath: keyPath] = value
        updateRouteFilters(updated)
    }
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        RouteOptionsBar(
            filters: RoutePlannerFilters(),
            hasDestination: true,
            updateRouteFilters: { _ in },
            saveCurrentCommutePreset: { _ in }
        )
        .padding()
    }
#endif
