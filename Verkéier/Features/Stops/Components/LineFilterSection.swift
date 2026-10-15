import SwiftUI

/// The lines serving a stop, as a scrolling row of filter badges.
struct LineFilterSection: View {
    let routes: [TransitRoute]
    let selectedLine: String?
    let toggleDepartureLine: (TransitRoute) -> Void

    var body: some View {
        if !routes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routes.prefix(16)) { route in
                        LineFilterBadge(
                            route: route,
                            isSelected: route.id == selectedLine,
                            isDimmed: selectedLine != nil && route.id != selectedLine,
                            toggleDepartureLine: { toggleDepartureLine(route) }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    NavigationStack {
        LineFilterSection(
            routes: [
                TransitRoute(
                    id: "route-1",
                    shortName: "16",
                    longName: "Luxembourg – Kirchberg",
                    mode: .bus,
                    dataSource: .mock
                ),
                TransitRoute(
                    id: "route-2",
                    shortName: "T1",
                    longName: "Luxembourg Gare – Stadion",
                    mode: .tram,
                    dataSource: .mock
                ),
            ],
            selectedLine: "route-2",
            toggleDepartureLine: { _ in }
        )
        .padding()
    }
}
