import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FavouriteStopWidget: Widget {
    let kind = "FavouriteStopWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFavouriteStopIntent.self,
            provider: FavouriteStopTimelineProvider()
        ) { entry in
            FavouriteStopWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(
                    entry.selectedStop.map { TransitDeepLink.openStop(id: $0.id).url }
                        ?? TransitDeepLink.showNearbyStops.url
                )
        }
        .configurationDisplayName("Favourite Stop")
        .description("Choose which favourite stop opens from this widget.")
        .supportedFamilies([
            .systemSmall,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular
        ])
    }
}

private struct FavouriteStopWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavouriteStopEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.selectedStop?.name.stationDisplayName ?? "No favourite", systemImage: "star.fill")
        case .accessoryCircular:
            Image(systemName: "star.fill")
                .font(.title2)
                .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.selectedStop?.name.stationDisplayName ?? "No favourite", systemImage: "star.fill")
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.selectedStop?.locality ?? "Open for live departures")
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            systemSmallView
        }
    }

    @ViewBuilder
    private var systemSmallView: some View {
        if let stop = entry.selectedStop {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Spacer(minLength: 0)
                Text(stop.name.stationDisplayName)
                    .font(.headline)
                    .lineLimit(2)
                Text(stop.locality ?? "Favourite stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Open for live departures")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "star")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("No favourites")
                    .font(.headline)
                Text("Save a stop in Verkéier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
