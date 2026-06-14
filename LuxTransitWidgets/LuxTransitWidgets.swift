import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LuxTransitWidgets: WidgetBundle {
    var body: some Widget {
        FavouriteStopWidget()
        DeparturesSummaryWidget()
        DepartureCountdownActivityWidget()
    }
}

private struct FavouriteStopEntry: TimelineEntry {
    let date: Date
    let favouriteStops: [SharedFavouriteStop]
}

private struct FavouriteStopTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavouriteStopEntry {
        FavouriteStopEntry(
            date: .now,
            favouriteStops: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FavouriteStopEntry) -> Void) {
        completion(
            FavouriteStopEntry(date: .now, favouriteStops: SharedTransitDataStore.favouriteStops()))
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<FavouriteStopEntry>) -> Void
    ) {
        let entry = FavouriteStopEntry(
            date: .now, favouriteStops: SharedTransitDataStore.favouriteStops())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private struct FavouriteStopWidget: Widget {
    let kind = "FavouriteStopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavouriteStopTimelineProvider()) { entry in
            FavouriteStopWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(
                    entry.favouriteStops.first.map { TransitDeepLink.openStop(id: $0.id).url }
                        ?? TransitDeepLink.showNearbyStops.url)
        }
        .configurationDisplayName("Favourite Stop")
        .description("Shows a saved stop. Open the app for live departures.")
        .supportedFamilies([.systemSmall])
    }
}

private struct FavouriteStopWidgetView: View {
    let entry: FavouriteStopEntry

    var body: some View {
        if let stop = entry.favouriteStops.first {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Spacer(minLength: 0)
                Text(stop.name)
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
                Text("Save a stop in LuxTransit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct DeparturesSummaryWidget: Widget {
    let kind = "DeparturesSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavouriteStopTimelineProvider()) { entry in
            DeparturesSummaryWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(
                    entry.favouriteStops.first.map {
                        TransitDeepLink.showDepartures(stopId: $0.id).url
                    } ?? TransitDeepLink.showNearbyStops.url)
        }
        .configurationDisplayName("Departures")
        .description(
            "A favourite-stop launcher. Widgets refresh periodically and are not continuously live."
        )
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
                Text("Not live")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            if let stop = entry.favouriteStops.first {
                Text(stop.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("Open LuxTransit for real-time ATP departures, delays, and cancellations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Choose a favourite stop")
                    .font(.title3.weight(.semibold))
                Text("Save a stop in the app to make this widget useful.")
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

private struct DepartureCountdownActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            DepartureLockScreenView(context: context)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(Color.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.lineName)
                        .font(.title3.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusText)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.destination)
                            .font(.subheadline.weight(.semibold))
                        Text(context.attributes.stopName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.attributes.lineName)
                    .font(.caption.weight(.bold))
            } compactTrailing: {
                if let departureDate = context.state.displayDepartureDate {
                    Text(timerInterval: .now...departureDate, countsDown: true)
                        .monospacedDigit()
                } else {
                    Image(systemName: "clock")
                }
            } minimal: {
                Image(systemName: context.state.isCancelled ? "xmark.octagon.fill" : "bus.fill")
            }
        }
    }
}

private struct DepartureLockScreenView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Text(context.attributes.lineName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 42)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.destination)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.attributes.stopName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let departureDate = context.state.displayDepartureDate {
                    Text(timerInterval: .now...departureDate, countsDown: true)
                        .font(.headline.monospacedDigit())
                } else {
                    Text("Time unknown")
                        .font(.caption)
                }
                Text(context.state.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
        }
        .padding()
    }

    private var statusColor: Color {
        if context.state.isCancelled { return .red }
        if let delay = context.state.delayMinutes, delay > 0 { return .orange }
        return .secondary
    }
}
