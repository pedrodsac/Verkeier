import SwiftUI

struct FavouriteStopDepartureCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stop: Stop
    let departures: [Departure]
    let isExpanded: Bool
    let selectStop: () -> Void
    let toggleExpansion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: selectStop) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: stop.modes.primaryMode.symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(transitColor.gradient, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(stop.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(primarySummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let secondarySummary {
                            Text(secondarySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Button(action: toggleExpansion) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse departures" : "Expand departures")
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    Divider().padding(.leading, 62)
                    if departures.isEmpty {
                        Text("No live departures available")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(departures.prefix(3)) { departure in
                            DepartureListRow(departure: departure, showsControls: false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .background(
            .background.opacity(0.76), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(.separator.opacity(0.22), lineWidth: 0.5)
        }
        .animation(Animation.respectingReduceMotion(.snappy(duration: 0.22), reduceMotion), value: isExpanded)
    }

    private var primarySummary: String {
        guard let departure = departures.first else {
            return stop.locality ?? "Tap to view departures"
        }
        return "\(departure.lineName) \(departure.destination) · \(departure.status.displayText)"
    }

    private var secondarySummary: String? {
        guard departures.count > 1 else { return nil }
        let departure = departures[1]
        return "\(departure.lineName) \(departure.destination) · \(departure.status.displayText)"
    }

    private var transitColor: Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return .blue
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    FavouriteStopDepartureCard(
        stop: Stop(
            id: "200209001",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
            modes: [.bus, .tram],
            dataSource: .mock
        ),
        departures: [
            Departure(
                id: "dep-1",
                stopId: "200209001",
                lineName: "16",
                destination: "Kirchberg",
                scheduledDeparture: .now.addingTimeInterval(180),
                realtimeDeparture: .now.addingTimeInterval(240),
                delayMinutes: 1,
                dataSource: .mock
            ),
            Departure(
                id: "dep-2",
                stopId: "200209001",
                lineName: "T1",
                destination: "Rout Bréck–Pafendall",
                scheduledDeparture: .now.addingTimeInterval(480),
                dataSource: .mock
            )
        ],
        isExpanded: true,
        selectStop: {},
        toggleExpansion: {}
    )
    .padding(.horizontal, 16)
}
