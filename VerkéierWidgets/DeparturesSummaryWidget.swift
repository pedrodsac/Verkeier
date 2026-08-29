import AppIntents
import SwiftUI
import WidgetKit

struct DeparturesSummaryWidget: Widget {
    static let kind = "DeparturesSummaryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectFavouriteStopIntent.self,
            provider: LiveDeparturesTimelineProvider()
        ) { entry in
            LiveDeparturesWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(entry.destinationURL)
        }
        .configurationDisplayName("Live Departures")
        .description("See the next departures from a favourite stop.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct LiveDeparturesWidgetView: View {
    let entry: LiveDeparturesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)

            content
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.stop?.name.stationDisplayName ?? "Live departures")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(entry.updateLabel)
                    .font(.caption2)
                    .foregroundStyle(entry.isStale ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if entry.stop == nil {
            WidgetMessage(
                icon: "star",
                title: "Choose a favourite stop",
                detail: "Touch and hold the widget to edit it."
            )
        } else if entry.departures.isEmpty {
            WidgetMessage(
                icon: "arrow.clockwise",
                title: "No departures available",
                detail: "Open Verkéier to refresh live data."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entry.departures.prefix(3).enumerated()), id: \.element.id) { index, departure in
                    DepartureRow(departure: departure, referenceDate: entry.date)
                    if index < min(entry.departures.count, 3) - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }
}

private struct DepartureRow: View {
    let departure: SharedWidgetDeparture
    let referenceDate: Date

    var body: some View {
        HStack(spacing: 10) {
            Text(departure.lineName.isEmpty ? "—" : departure.lineName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: 36, height: 26)
                .background(routeColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(departure.destination.isEmpty ? "Destination unavailable" : departure.destination)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(departureDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(countdownLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(countdownColor)
                .monospacedDigit()
                .fixedSize()
        }
        .frame(height: 33)
        .accessibilityElement(children: .combine)
    }

    private var departureDetail: String {
        var parts: [String] = []
        if let date = departure.displayDepartureDate {
            parts.append(date.formatted(date: .omitted, time: .shortened))
        }
        if let platform = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
           !platform.isEmpty {
            parts.append("Platform \(platform)")
        }
        return parts.isEmpty ? "Time unavailable" : parts.joined(separator: " · ")
    }

    private var countdownLabel: String {
        guard !departure.isCancelled else { return "Cancelled" }
        guard let date = departure.displayDepartureDate else { return "—" }
        let seconds = date.timeIntervalSince(referenceDate)
        if seconds <= 30 { return "Now" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }

    private var countdownColor: Color {
        if departure.isCancelled { return .red }
        if (departure.delayMinutes ?? 0) > 0 { return .orange }
        return .primary
    }

    private var routeColor: Color {
        departure.lineName.uppercased().hasPrefix("T") ? .orange : .blue
    }
}

private struct WidgetMessage: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
