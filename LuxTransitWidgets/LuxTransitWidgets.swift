import ActivityKit
import AppIntents
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

struct WidgetFavouriteStopEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favourite Stop")
    static let defaultQuery = WidgetFavouriteStopEntityQuery()

    let id: String
    let name: String
    let locality: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: locality.map { "\($0)" }
        )
    }
}

struct WidgetFavouriteStopEntityQuery: EntityQuery {
    func entities(for identifiers: [WidgetFavouriteStopEntity.ID]) async throws
        -> [WidgetFavouriteStopEntity] {
        sharedStops().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFavouriteStopEntity] {
        sharedStops()
    }

    func defaultResult() async -> WidgetFavouriteStopEntity? {
        sharedStops().first
    }

    private func sharedStops() -> [WidgetFavouriteStopEntity] {
        SharedTransitDataStore.favouriteStops().map {
            WidgetFavouriteStopEntity(id: $0.id, name: $0.name, locality: $0.locality)
        }
    }
}

struct SelectFavouriteStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Favourite Stop"
    static let description = IntentDescription("Pick which saved favourite stop this widget opens.")

    @Parameter(title: "Stop")
    var stop: WidgetFavouriteStopEntity?
}

private struct FavouriteStopEntry: TimelineEntry {
    let date: Date
    let selectedStop: SharedFavouriteStop?
}

private struct FavouriteStopTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> FavouriteStopEntry {
        FavouriteStopEntry(date: .now, selectedStop: SharedTransitDataStore.favouriteStops().first)
    }

    func snapshot(for configuration: SelectFavouriteStopIntent, in _: Context) async
        -> FavouriteStopEntry {
        FavouriteStopEntry(date: .now, selectedStop: selectedStop(from: configuration))
    }

    func timeline(for configuration: SelectFavouriteStopIntent, in _: Context) async
        -> Timeline<FavouriteStopEntry> {
        let entry = FavouriteStopEntry(date: .now, selectedStop: selectedStop(from: configuration))
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func selectedStop(from configuration: SelectFavouriteStopIntent) -> SharedFavouriteStop? {
        let stops = SharedTransitDataStore.favouriteStops()
        if let stopID = configuration.stop?.id {
            return stops.first(where: { $0.id == stopID }) ?? stops.first
        }
        return stops.first
    }
}

private struct FavouriteStopWidget: Widget {
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
            Label(entry.selectedStop?.name ?? "No favourite", systemImage: "star.fill")
        case .accessoryCircular:
            Image(systemName: "star.fill")
                .font(.title2)
                .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.selectedStop?.name ?? "No favourite", systemImage: "star.fill")
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
                    Text(timerInterval: .now ... departureDate, countsDown: true)
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
                    Text(timerInterval: .now ... departureDate, countsDown: true)
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
