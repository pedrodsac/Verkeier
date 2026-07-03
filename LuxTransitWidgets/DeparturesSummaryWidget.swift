import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct DeparturesSummaryWidget: Widget {
    let kind = "DeparturesSummaryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFavouriteStopIntent.self,
            provider: FavouriteStopTimelineProvider()
        ) { entry in
            DeparturesSummaryWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(
                    entry.selectedStop.map {
                        TransitDeepLink.showDepartures(stopId: $0.id).url
                    } ?? TransitDeepLink.showNearbyStops.url
                )
        }
        .configurationDisplayName("Departures")
        .description("Choose a favourite stop. This widget refreshes periodically and is not continuously live.")
        .supportedFamilies([.systemMedium])
    }
}

private struct DeparturesSummaryWidgetView: View {
    let entry: FavouriteStopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Departures", systemImage: "clock.fill")
                    .font(.headline)
                Spacer()
                Text("Periodic")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            if let stop = entry.selectedStop {
                Text(stop.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("Open LuxTransit for live ATP departures, delay updates, and cancellation details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Choose a favourite stop")
                    .font(.title3.weight(.semibold))
                Text("Save a stop in the app, then configure this widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
