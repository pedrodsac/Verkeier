import SwiftUI

/// A tappable route-option card displaying departure/arrival times, a
/// ``RouteRibbon`` of mode/line badges, and a status badge.
///
/// Matches the Apple Maps Transit result row style: time range + duration on
/// top, the mode ribbon as the dominant visual, metadata on the bottom.
struct RouteOptionCard: View {
    let option: RouteOption
    let isSelected: Bool
    let selectRouteOption: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: selectRouteOption) {
            VStack(alignment: .leading, spacing: 8) {
                // ── Header: time range / duration / status badge ──────────
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(timeRangeText)
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text("  ·  \(durationText)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    RouteOptionBadge(status: option.status(at: .now))
                }

                // ── Mode / line ribbon ────────────────────────────────────
                RouteRibbon(legs: option.plan.legs)

                // ── Secondary metadata ────────────────────────────────────
                Text(secondarySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(cardStroke, lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .animation(Animation.respectingReduceMotion(.snappy(duration: 0.22), reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Opens route step-by-step timeline")
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Computed properties

    private var timeRangeText: String {
        let departure = option.firstTransitDepartureTime
        let arrival = option.arrivalTime

        switch (departure, arrival) {
        case let (.some(dep), .some(arr)):
            return "\(dep.formatted(date: .omitted, time: .shortened)) – \(arr.formatted(date: .omitted, time: .shortened))"
        case let (.some(dep), .none):
            return dep.formatted(date: .omitted, time: .shortened)
        default:
            return "Scheduled route"
        }
    }

    private var durationText: String {
        let duration = option.plan.expectedTravelTime ?? 0
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes) min"
    }

    private var secondarySummary: String {
        let transfers = switch option.transferCount {
        case 0: "Direct"
        case 1: "1 transfer"
        default: "\(option.transferCount) transfers"
        }

        let distance = preferences.formattedDistance(option.plan.distanceMeters ?? 0)
        let dataNote = option.usesLiveData ? "Live" : "Scheduled"

        return "\(transfers)  ·  \(distance)  ·  \(dataNote)"
    }

    private var cardBackground: AnyShapeStyle {
        AnyShapeStyle(
            Color(uiColor: .systemBackground)
                .opacity(isSelected ? 0.95 : 0.78)
        )
    }

    private var cardStroke: Color {
        isSelected
            ? .blue.opacity(0.5)
            : Color(uiColor: .separator).opacity(0.22)
    }

    private var accessibilityLabel: String {
        "\(timeRangeText), \(durationText). \(secondarySummary)"
    }
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        VStack(spacing: 10) {
            RouteOptionCard(
                option: .previewTramOption,
                isSelected: true,
                selectRouteOption: {}
            )
            RouteOptionCard(
                option: .previewBusOption,
                isSelected: false,
                selectRouteOption: {}
            )
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(AppPreferences())
    }

    private extension RouteOption {
        static var previewTramOption: RouteOption {
            RouteOption(
                id: "tram-route",
                plan: RoutePlan(
                    id: "tram-plan",
                    origin: LocationPoint(id: "o", name: "Origin", latitude: 49.6116, longitude: 6.1319),
                    destination: LocationPoint(id: "d", name: "Dest", latitude: 49.6329, longitude: 6.1746),
                    expectedTravelTime: 18 * 60,
                    distanceMeters: 4300,
                    legs: [
                        RoutePlan.Leg(
                            id: "walk1",
                            mode: .walking,
                            transportKind: .walking,
                            origin: LocationPoint(id: "o", name: "Origin", latitude: 49.6116, longitude: 6.1319),
                            destination: LocationPoint(id: "h", name: "Hamilius", latitude: 49.6111, longitude: 6.1275),
                            departureTime: Date(),
                            arrivalTime: Date().addingTimeInterval(4 * 60),
                            distanceMeters: 350
                        ),
                        RoutePlan.Leg(
                            id: "tram1",
                            mode: .tram,
                            transportKind: .transit,
                            routeName: "T1",
                            origin: LocationPoint(id: "h", name: "Hamilius", latitude: 49.6111, longitude: 6.1275),
                            destination: LocationPoint(id: "d", name: "Dest", latitude: 49.6329, longitude: 6.1746),
                            departureTime: Date().addingTimeInterval(6 * 60),
                            arrivalTime: Date().addingTimeInterval(18 * 60),
                            realtimeDepartureTime: Date().addingTimeInterval(7 * 60),
                            realtimeArrivalTime: Date().addingTimeInterval(19 * 60),
                            distanceMeters: 3950,
                            delayMinutes: 1,
                            liveStatus: .live
                        )
                    ],
                    dataSource: .mock
                ),
                mapOverlay: nil
            )
        }

        static var previewBusOption: RouteOption {
            RouteOption(
                id: "bus-route",
                plan: RoutePlan(
                    id: "bus-plan",
                    origin: LocationPoint(id: "o", name: "Origin", latitude: 49.6116, longitude: 6.1319),
                    destination: LocationPoint(id: "d", name: "Dest", latitude: 49.6329, longitude: 6.1746),
                    expectedTravelTime: 24 * 60,
                    distanceMeters: 4800,
                    legs: [
                        RoutePlan.Leg(
                            id: "bus1",
                            mode: .bus,
                            transportKind: .transit,
                            routeName: "16",
                            origin: LocationPoint(id: "o", name: "Origin", latitude: 49.6116, longitude: 6.1319),
                            destination: LocationPoint(id: "d", name: "Dest", latitude: 49.6329, longitude: 6.1746),
                            departureTime: Date().addingTimeInterval(9 * 60),
                            arrivalTime: Date().addingTimeInterval(24 * 60),
                            distanceMeters: 4800
                        )
                    ],
                    dataSource: .mock
                ),
                mapOverlay: nil
            )
        }
    }
#endif
