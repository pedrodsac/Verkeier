import SwiftUI

/// One line serving a stop. Tapping it filters the departures to that line;
/// its menu opens the line's details.
struct LineFilterBadge: View {
    let route: TransitRoute
    let isSelected: Bool
    let isDimmed: Bool
    let toggleDepartureLine: () -> Void

    var body: some View {
        Menu {
            NavigationLink(value: SheetRoute.lineDetail(route)) {
                Label("Information", systemImage: "info.circle")
            }
        } label: {
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
        } primaryAction: {
            toggleDepartureLine()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    init(
        route: TransitRoute,
        isSelected: Bool = false,
        isDimmed: Bool = false,
        toggleDepartureLine: @escaping () -> Void = {}
    ) {
        self.route = route
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.toggleDepartureLine = toggleDepartureLine
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
