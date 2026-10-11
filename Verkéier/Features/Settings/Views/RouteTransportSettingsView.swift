import SwiftUI

struct RouteTransportSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        List {
            ForEach(RoutePlannerFilters.selectableModes) { mode in
                Toggle(isOn: Binding(
                    get: { preferences.includedRouteModes.contains(mode) },
                    set: { included in
                        if included { preferences.includedRouteModes.insert(mode) }
                        else { preferences.includedRouteModes.remove(mode) }
                    }
                )) {
                    Label {
                        Text(LocalizedStringKey(mode.displayName))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: mode.symbolName)
                            .foregroundStyle(mode.tint)
                    }
                }
            }
        }
        .symbolRenderingMode(.hierarchical)
        .navigationTitle("Transport in routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RouteTransportSettingsView()
    }
    .environment(AppPreferences())
}
