import SwiftUI

/// A prominent "next departure" card surfaced above the departure list so the
/// single most useful fact — when the next ride leaves — isn't buried in row 1.
///
/// The countdown refreshes on its own via a ``TimelineView`` rather than forcing
/// the whole board to re-render.
struct NextDepartureHeroCard: View {
    let departure: Departure

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let kind = DepartureTransportKind(lineName: departure.lineName)

        TimelineView(.periodic(from: .now, by: 30)) { context in
            let countdown = countdownText(now: context.date)
            HStack(spacing: 14) {
                lineChip(kind: kind)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Next departure")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(departure.destination)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    if let platform = departure.platform {
                        Text("Platform \(platform)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdown)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(delayMinutes == nil ? Color.primary : Color.orange)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(Animation.respectingReduceMotion(.snappy, reduceMotion), value: countdown)
                    if let delay = delayMinutes {
                        Text("Delayed +\(delay)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .background(
                .background.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .stroke(kind.color.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .accessibilityElement(children: .combine)
        }
    }

    private func lineChip(kind: DepartureTransportKind) -> some View {
        HStack(spacing: 5) {
            Image(systemName: kind.icon)
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(departure.lineName)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 56, minHeight: 40)
        .padding(.horizontal, 8)
        .background(kind.color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var departureDate: Date? {
        departure.realtimeDeparture ?? departure.scheduledDeparture
    }

    private var delayMinutes: Int? {
        if case let .delayed(minutes) = departure.status { return minutes }
        return nil
    }

    private func countdownText(now: Date) -> String {
        guard let departureDate else { return "—" }
        let minutes = Int(departureDate.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "Now" }
        if minutes < 90 { return "in \(minutes) min" }
        return departureDate.formatted(date: .omitted, time: .shortened)
    }
}

/// IDs of departures that are the last service of the day for their line.
///
/// A departure qualifies when no later departure for the same ``Departure/lineName``
/// exists in `departures` and it leaves after 18:00 local time — the cutoff keeps
/// the badge off early-morning boards that are merely a snapshot. Cancelled trips
/// are ignored.
nonisolated func lastServiceDepartureIDs(
    in departures: [Departure],
    calendar: Calendar = .current
) -> Set<String> {
    func time(_ departure: Departure) -> Date? {
        departure.realtimeDeparture ?? departure.scheduledDeparture
    }

    var latestByLine: [String: Departure] = [:]
    for departure in departures where !departure.isCancelled {
        guard let departureTime = time(departure) else { continue }
        if let existing = latestByLine[departure.lineName],
           let existingTime = time(existing),
           existingTime >= departureTime {
            continue
        }
        latestByLine[departure.lineName] = departure
    }

    return Set(latestByLine.values.compactMap { departure in
        guard let departureTime = time(departure),
              calendar.component(.hour, from: departureTime) >= 18 else { return nil }
        return departure.id
    })
}

#if DEBUG
    #Preview(traits: .sizeThatFitsLayout) {
        NextDepartureHeroCard(
            departure: Departure(
                id: "dep-1",
                stopId: "stop-1",
                lineName: "T1",
                destination: "Luxexpo",
                scheduledDeparture: Date().addingTimeInterval(4 * 60),
                realtimeDeparture: Date().addingTimeInterval(7 * 60),
                delayMinutes: 3,
                platform: "2",
                dataSource: .mock
            )
        )
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
    }
#endif
