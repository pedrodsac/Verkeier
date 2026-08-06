import SwiftUI

struct StopDetailHeader: View {
    let stop: Stop
    let routes: [TransitRoute]
    let selectedLine: String?
    let openDirections: () -> Void
    let toggleDepartureLine: (TransitRoute) -> Void
    let showLineDetail: (TransitRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StopMetadataPanel(
                routes: routes,
                selectedLine: selectedLine,
                toggleDepartureLine: toggleDepartureLine,
                showLineDetail: showLineDetail
            )

            if stop.wheelchairBoarding != .unknown {
                Label(
                    stop.wheelchairBoarding == .accessible
                        ? "Wheelchair accessible" : "Not wheelchair accessible",
                    systemImage: stop.wheelchairBoarding == .accessible
                        ? "figure.roll" : "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(stop.wheelchairBoarding == .accessible ? .green : .orange)
                .accessibilityLabel(
                    stop.wheelchairBoarding == .accessible
                        ? "Step-free, wheelchair accessible" : "Not wheelchair accessible"
                )
            }

            DirectionsButton(openDirections: openDirections)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for stop: Stop) -> String {
        if stop.modes.contains(.train) { return "train.side.front.car" }
        if stop.modes.contains(.tram) { return "tram.fill" }
        if stop.modes.contains(.funicular) { return "cablecar.fill" }
        return "bus.fill"
    }

    private func color(for stop: Stop) -> Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return .blue
    }
}

private struct StopMetadataPanel: View {
    let routes: [TransitRoute]
    let selectedLine: String?
    let toggleDepartureLine: (TransitRoute) -> Void
    let showLineDetail: (TransitRoute) -> Void

    var body: some View {
        if !routes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routes.prefix(16)) { route in
                        RouteLineCard(
                            route: route,
                            isSelected: route.id == selectedLine,
                            isDimmed: selectedLine != nil && route.id != selectedLine,
                            toggleDepartureLine: { toggleDepartureLine(route) },
                            showLineDetail: { showLineDetail(route) }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct RouteLineCard: View {
    let route: TransitRoute
    let isSelected: Bool
    let isDimmed: Bool
    let toggleDepartureLine: () -> Void
    let showLineDetail: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleDepartureLine) {
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .accessibilityHidden(true)
                    Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                        .lineLimit(1)
                }
                .font(.callout.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(cardColor.opacity(isSelected ? 0.20 : 0.14), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        cardColor.opacity(isSelected ? 0.55 : 0.25),
                        lineWidth: isSelected ? 1.1 : 0.7
                    )
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .contextMenu {
            Button(action: showLineDetail) {
                Label("Information", systemImage: "info.circle")
            }
        }
    }

    init(
        route: TransitRoute,
        isSelected: Bool = false,
        isDimmed: Bool = false,
        toggleDepartureLine: @escaping () -> Void = {},
        showLineDetail: @escaping () -> Void = {}
    ) {
        self.route = route
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.toggleDepartureLine = toggleDepartureLine
        self.showLineDetail = showLineDetail
    }

    private var iconName: String {
        switch route.mode {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .bicycle: "bicycle"
        case .walking: "figure.walk"
        case .unknown: "circle"
        }
    }

    private var routeColor: Color {
        switch route.mode {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .bicycle: .teal
        case .walking, .unknown: .secondary
        }
    }

    private var cardColor: Color {
        isDimmed ? .secondary : routeColor
    }
}

struct RouteChip: View {
    let route: TransitRoute
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                .lineLimit(1)
        }
        .font(.callout.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(routeColor.opacity(isSelected ? 0.20 : 0.14), in: Capsule())
        .overlay {
            Capsule().stroke(
                routeColor.opacity(isSelected ? 0.55 : 0.25),
                lineWidth: isSelected ? 1.1 : 0.7
            )
        }
    }

    private var iconName: String {
        switch route.mode {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .bicycle: "bicycle"
        case .walking: "figure.walk"
        case .unknown: "circle"
        }
    }

    private var routeColor: Color {
        switch route.mode {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .bicycle: .teal
        case .walking, .unknown: .secondary
        }
    }
}

private struct DirectionsButton: View {
    let openDirections: () -> Void

    var body: some View {
        Button(action: openDirections) {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.blue, in: Capsule())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get directions")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    RouteChip(
        route: TransitRoute(
            id: "route-1",
            shortName: "16",
            longName: "Luxembourg – Kirchberg",
            mode: .bus,
            dataSource: .mock
        ),
        isSelected: false
    )
}

#Preview(traits: .sizeThatFitsLayout) {
    RouteChip(
        route: TransitRoute(
            id: "route-2",
            shortName: "T1",
            longName: "Luxembourg Gare – Stadion",
            mode: .tram,
            dataSource: .mock
        ),
        isSelected: true
    )
}
