import AppIntents
import SwiftUI
import WidgetKit

struct DeparturesSummaryWidget: Widget {
    let kind = "DeparturesSummaryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectFavouriteStopIntent.self, provider: FavouriteStopTimelineProvider()) { entry in
            LiveDeparturesWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
                .widgetURL(entry.selectedStop.map { TransitDeepLink.showDepartures(stopId: $0.id).url } ?? TransitDeepLink.showNearbyStops.url)
        }
        .configurationDisplayName("Live Departures")
        .description("Upcoming departures for a favourite stop.")
        .supportedFamilies([.systemMedium])
    }
}

private struct LiveDeparturesWidgetView: View {
    let entry: FavouriteStopEntry

    private var upcoming: [SharedWidgetDeparture] {
        let cutoff = entry.date.addingTimeInterval(-60)
        return Array((entry.departureBoard?.departures ?? [])
            .filter { ($0.displayDepartureDate ?? .distantFuture) >= cutoff }
            .prefix(3))
    }

    var body: some View {
        VStack(spacing: 9) {
            header
            if entry.selectedStop == nil {
                emptyState("Choose a favourite stop", icon: "star")
            } else if upcoming.isEmpty {
                emptyState("Open Verkéier to refresh departures", icon: "arrow.clockwise")
            } else {
                VStack(spacing: 6) {
                    ForEach(upcoming) { WidgetDepartureRow(departure: $0) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.selectedStop?.name.stationDisplayName ?? "Live departures")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                if let board = entry.departureBoard {
                    Text(board.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(entry.date.timeIntervalSince(board.updatedAt) > 900 ? .orange : .secondary)
                } else {
                    Text("Favourite stop").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

private struct WidgetDepartureRow: View {
    let departure: SharedWidgetDeparture

    var body: some View {
        HStack(spacing: 9) {
            Text(departure.lineName)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 38, height: 27)
                .background(lineColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(departure.destination.isEmpty ? "Destination unknown" : departure.destination)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if let date = departure.displayDepartureDate { Text(date, style: .time) }
                    if let platform = departure.platform, !platform.isEmpty { Text("· Platform \(platform)") }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            countdown
                .font(.caption.weight(.bold))
                .fixedSize()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var countdown: some View {
        if departure.isCancelled {
            Text("Cancelled").foregroundStyle(.red)
        } else if let date = departure.displayDepartureDate {
            Text(timerInterval: Date.now...max(date, Date.now), countsDown: true)
                .monospacedDigit()
                .foregroundStyle((departure.delayMinutes ?? 0) > 0 ? .orange : .primary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private var lineColor: Color {
        let name = departure.lineName.uppercased()
        if name.hasPrefix("T") { return .blue }
        if name.range(of: #"^\d+$"#, options: .regularExpression) != nil { return .indigo }
        return .teal
    }
}

private struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 190, height: 190)
                .blur(radius: 35)
                .offset(x: 145, y: -75)
        }
    }
}
