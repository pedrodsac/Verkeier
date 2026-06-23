import SwiftUI

/// A compact single-row filter bar: sort tabs on the left, an advanced
/// options menu on the right.
///
/// The sort Picker collapses three options into a segmented control; the gear
/// `Menu` contains mode-preference, accessibility toggles, and Save Commute —
/// keeping the planner screen uncluttered.
struct RouteOptionsBar: View {
    let filters: RoutePlannerFilters
    let hasDestination: Bool
    let updateRouteFilters: (RoutePlannerFilters) -> Void
    let saveCurrentCommutePreset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
			sortPicker
            optionsMenu
        }
    }

    // MARK: - Sort picker

    private var sortPicker: some View {
        Picker(
            "Sort routes",
            selection: Binding(
                get: { filters.sort },
                set: { updated in apply(\.sort, value: updated) }
            )
        ) {
            Text("Fastest").tag(RoutePlannerSortOption.fastest)
            Text("Transfers").tag(RoutePlannerSortOption.fewestTransfers)
            Text("Walking").tag(RoutePlannerSortOption.leastWalking)
        }
        .pickerStyle(.segmented)
		.frame(maxWidth: .infinity)
    }

    // MARK: - Options menu

    private var optionsMenu: some View {
        Menu {
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

            Toggle(
                "Prefer accessible options",
                isOn: Binding(
                    get: { filters.preferAccessible },
                    set: { updated in apply(\.preferAccessible, value: updated) }
                )
            )

            if hasDestination {
                Divider()
                Button("Save Commute", action: saveCurrentCommutePreset)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(
                    .background.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator.opacity(0.22), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
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
        saveCurrentCommutePreset: {}
    )
    .padding()
}
#endif
