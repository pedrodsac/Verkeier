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

            VStack(alignment: .leading, spacing: 0) {
                metadata

                Text(entry.stop?.displayName ?? "Live departures")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(intent: RefreshDeparturesWidgetIntent(stopID: entry.stop?.id)) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh departures")
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if let locality = entry.stop?.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
               !locality.isEmpty {
                Text(locality)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.secondary)
            }

            Text(entry.updateLabel)
                .foregroundStyle(entry.isStale ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
        .font(.caption2)
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

                departureDetail
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(countdownLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(countdownColor)

                if let statusLabel {
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
        .frame(height: 33)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var departureDetail: some View {
        HStack(spacing: 4) {
            if isLate,
               let scheduled = departure.scheduledDeparture,
               let realtime = departure.realtimeDeparture {
                Text(formattedTime(scheduled))
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text(formattedTime(realtime))
                    .foregroundStyle(.orange)
            } else if let date = departure.displayDepartureDate {
                Text(formattedTime(date))
                    .foregroundStyle(.secondary)
            } else {
                Text("Time unavailable")
                    .foregroundStyle(.secondary)
            }

            if let platform = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
               !platform.isEmpty {
                Text("· Platform \(platform)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    private var countdownLabel: String {
        guard !departure.isCancelled else { return "Cancelled" }
        guard let date = departure.displayDepartureDate else { return "—" }
        let minutes = SharedDepartureTiming.countdownMinutes(until: date, from: referenceDate)
        return minutes == 0 ? "Now" : "\(minutes) min"
    }

    private var statusLabel: String? {
        guard !departure.isCancelled else { return nil }
        if let delayMinutes = departure.delayMinutes {
            return delayMinutes > 0 ? "+\(delayMinutes) min" : "On time"
        }
        return nil
    }

    private var statusColor: Color {
        isLate ? .orange : .green
    }

    private var countdownColor: Color {
        if departure.isCancelled { return .red }
        if isLate { return .orange }
        return .primary
    }

    private var isLate: Bool {
        (departure.delayMinutes ?? 0) > 0
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
