import SwiftUI

/// An Apple Maps-style horizontal sequence of mode/line badges and walking
/// segments that summarises a multi-leg journey at a glance.
///
/// Transit legs show a solid line badge (white text on the mode's gradient).
/// Walking legs show a walking icon and optional duration.
/// Segments are separated by chevrons.
///
///     🚶 4m  ›  🟧 T1  ›  🚶 2m
///
struct RouteRibbon: View {
    let legs: [RoutePlan.Leg]

    private var displayLegs: [RoutePlan.Leg] {
        legs.filter { $0.transportKind == .transit || $0.transportKind == .walking }
    }

    var body: some View {
        if displayLegs.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 7.5) {
                    ForEach(Array(displayLegs.enumerated()), id: \.element.id) { index, leg in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        ribbonSegment(for: leg)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    @ViewBuilder
    private func ribbonSegment(for leg: RoutePlan.Leg) -> some View {
        switch leg.transportKind {
        case .transit:
            TransitBadge(
                routeName: leg.routeName ?? leg.mode.displayName,
                mode: leg.mode
            )
        case .walking:
            WalkingSegment(minutes: walkMinutes(for: leg))
        default:
            EmptyView()
        }
    }

    private func walkMinutes(for leg: RoutePlan.Leg) -> Int? {
        let dep = leg.realtimeDepartureTime ?? leg.scheduledDepartureTime ?? leg.departureTime
        let arr = leg.realtimeArrivalTime ?? leg.scheduledArrivalTime ?? leg.arrivalTime
        guard let dep, let arr else { return nil }
        let minutes = Int((arr.timeIntervalSince(dep) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    private var accessibilityDescription: String {
        displayLegs.compactMap { leg -> String? in
            switch leg.transportKind {
            case .transit:
                let name = leg.routeName ?? leg.mode.displayName
                return "\(leg.mode.displayName) \(name)"
            case .walking:
                if let mins = walkMinutes(for: leg) {
                    return "Walk \(mins) minutes"
                }
                return "Walk"
            default:
                return nil
            }
        }.joined(separator: ", then ")
    }
}

// MARK: - Subviews

private struct TransitBadge: View {
    let routeName: String
    let mode: TransportMode

    var body: some View {
        Text(routeName)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                mode.tint.gradient,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct WalkingSegment: View {
    let minutes: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "figure.walk")
                .font(.caption.weight(.semibold))
            if let minutes {
                Text("\(minutes)m")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    RouteRibbon(legs: [
        RoutePlan.Leg(
            id: "walk1",
            mode: .walking,
            transportKind: .walking,
            origin: LocationPoint(id: "o", name: "Origin", latitude: 0, longitude: 0),
            destination: LocationPoint(id: "t", name: "Transfer", latitude: 0, longitude: 0),
            departureTime: Date(),
            arrivalTime: Date().addingTimeInterval(4 * 60),
            distanceMeters: 350
        ),
        RoutePlan.Leg(
            id: "tram1",
            mode: .tram,
            transportKind: .transit,
            routeName: "T1",
            origin: LocationPoint(id: "t", name: "Transfer", latitude: 0, longitude: 0),
            destination: LocationPoint(id: "d", name: "Dest", latitude: 0, longitude: 0),
            departureTime: Date().addingTimeInterval(6 * 60),
            arrivalTime: Date().addingTimeInterval(18 * 60)
        ),
        RoutePlan.Leg(
            id: "walk2",
            mode: .walking,
            transportKind: .walking,
            origin: LocationPoint(id: "d", name: "Dest", latitude: 0, longitude: 0),
            destination: LocationPoint(id: "f", name: "Final", latitude: 0, longitude: 0),
            departureTime: Date().addingTimeInterval(18 * 60),
            arrivalTime: Date().addingTimeInterval(20 * 60),
            distanceMeters: 120
        )
    ])
    .padding()
}
#endif
