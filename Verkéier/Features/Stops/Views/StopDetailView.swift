import SwiftUI

struct StopDetailView: View {
    let viewModel: StopDetailPresentationModel
    let actions: StopDetailActions

    private var departures: [Departure] { viewModel.displayedDepartures }

    private var departed: [Departure] {
        let now = Date()
        return Array(departures.filter {
            ($0.realtimeDeparture ?? $0.scheduledDeparture)
                .map { !SharedDepartureTiming.isVisible($0, at: now) } ?? false
        }.suffix(3))
    }

    private var upcoming: [Departure] {
        let now = Date()
        return departures.filter {
            ($0.realtimeDeparture ?? $0.scheduledDeparture)
                .map { SharedDepartureTiming.isVisible($0, at: now) } ?? true
        }
    }

    var body: some View {
        List {
            if let stop = viewModel.stop {
                if !viewModel.availablePlatforms.isEmpty {
                    PlatformFilterPicker(
                        platforms: viewModel.availablePlatforms,
                        selectedPlatform: viewModel.selectedPlatform,
                        selectPlatform: actions.selectDeparturePlatform
                    )
                    .listRowInsets(chromeRowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                StopDetailHeader(
                    stop: stop,
                    routes: viewModel.routes,
                    selectedLine: viewModel.selectedLine,
                    showDirections: actions.showDirections,
                    toggleDepartureLine: actions.toggleDepartureLine
                )
                .listRowInsets(chromeRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let liveActivityErrorMessage = viewModel.liveActivityErrorMessage {
                    Label(liveActivityErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .listRowInsets(actionRowInsets)
                        .listRowBackground(Color.orange.opacity(0.12))
                        .listRowSeparator(.hidden)
                }

                if let departureReminderErrorMessage = viewModel.departureReminderErrorMessage {
                    Label(departureReminderErrorMessage, systemImage: "bell.badge.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .listRowInsets(actionRowInsets)
                        .listRowBackground(Color.orange.opacity(0.12))
                        .listRowSeparator(.hidden)
                }

                if viewModel.isLoadingDepartures, departures.isEmpty {
                    DepartureLoadingCard(title: "Loading departures")
                        .listRowInsets(cardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if departures.isEmpty {
                    if let errorMessage = viewModel.errorMessage {
                        CompactUnavailableCard(
                            title: "Departures unavailable",
                            message: errorMessage,
                            systemImage: "wifi.exclamationmark"
                        )
                        .listRowInsets(cardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        CompactUnavailableCard(
                            title: "No departures",
                            message: "No live departures are available for this stop.",
                            systemImage: "clock.badge.exclamationmark"
                        )
                        .listRowInsets(cardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    let lastOfDayIDs = lastServiceDepartureIDs(in: departures)
                    let trackedDeparture = departures.first { $0.id == viewModel.trackedDepartureId }

                    if viewModel.isShowingScheduledFallback {
                        Label("Live updates unavailable · showing timetable", systemImage: "wifi.exclamationmark")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                            .listRowInsets(actionRowInsets)
                            .listRowBackground(Color.orange.opacity(0.12))
                            .listRowSeparator(.hidden)
                    }

                    if trackedDeparture != nil || viewModel.activeReminder != nil {
                        DepartureTrackingStatusCard(
                            trackedDeparture: trackedDeparture,
                            activeReminder: viewModel.activeReminder,
                            stopTrackingDeparture: actions.stopTrackingDeparture,
                            cancelDepartureReminder: actions.cancelDepartureReminder
                        )
                        .listRowInsets(cardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(departed, id: \.id) { departure in
                        DepartureListRow(departure: departure, showsControls: false)
                            .opacity(0.55)
                            .listRowInsets(departureRowInsets)
                    }

                    ForEach(upcoming, id: \.id) { departure in
                        DepartureListRow(
                            departure: departure,
                            isTracked: departure.id == viewModel.trackedDepartureId,
                            isLastOfDay: lastOfDayIDs.contains(departure.id),
                            showsControls: departure.dataSource != .gtfs,
                            activeReminder: viewModel.activeReminder,
                            startTrackingDeparture: { actions.startTrackingDeparture(departure) },
                            stopTrackingDeparture: actions.stopTrackingDeparture,
                            scheduleReminder: { minutes in
                                actions.scheduleDepartureReminder(departure, minutes)
                            },
                            cancelReminder: actions.cancelDepartureReminder
                        )
                        .listRowInsets(departureRowInsets)
                    }
                }

                if !viewModel.alerts.isEmpty {
                    StopDisruptionSection(alerts: viewModel.alerts)
                        .listRowInsets(cardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                CompactUnavailableCard(
                    title: "No stop selected",
                    message: "Choose a marker, favourite, nearby stop, or search result.",
                    systemImage: "bus"
                )
                .listRowInsets(cardRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // Haptic + VoiceOver feedback when the board refreshes with new data.
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.lastUpdated)
        .onChange(of: viewModel.lastUpdated) { _, newValue in
            if newValue != nil {
                AccessibilityNotification.Announcement("Departures updated").post()
            }
        }
    }

    private var chromeRowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    }

    private var actionRowInsets: EdgeInsets {
        EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    }

    private var cardRowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    }

    private var departureRowInsets: EdgeInsets {
        EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    }

}

private struct DepartureBoardAdvancedFilterMenu: View {
    let filter: TransitBoardFilter
    let update: (TransitBoardFilter) -> Void

    var body: some View {
        Menu {
            Section("Time window") {
                ForEach([30, 60, 120, 240], id: \.self) { duration in
                    Button(duration == filter.durationMinutes ? "✓ \(duration) minutes" : "\(duration) minutes") {
                        var copy = filter
                        copy.durationMinutes = duration
                        update(copy)
                    }
                }
            }
            Section("Results") {
                ForEach([5, 10, 20, 50], id: \.self) { count in
                    Button(count == filter.maximumJourneys ? "✓ \(count) departures" : "\(count) departures") {
                        var copy = filter
                        copy.maximumJourneys = count
                        update(copy)
                    }
                }
            }
            Section("Data") {
                Button(filter.realtimeMode == .full ? "✓ Live updates" : "Live updates") {
                    var copy = filter
                    copy.realtimeMode = .full
                    update(copy)
                }
                Button(filter.realtimeMode == .off ? "✓ Timetable only" : "Timetable only") {
                    var copy = filter
                    copy.realtimeMode = .off
                    update(copy)
                }
            }
            Button("Reset filters", role: .destructive) { update(TransitBoardFilter()) }
        } label: {
            Label("Board filters", systemImage: "line.3.horizontal.decrease.circle")
                .font(.callout.weight(.medium))
        }
    }
}

/// IDs of departures that are the last service of the day for their line.
///
/// A departure qualifies when no later departure for the same line exists in
/// `departures` and it leaves after 18:00 local time. Cancelled trips are
/// ignored.
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

private struct DepartureTrackingStatusCard: View {
    let trackedDeparture: Departure?
    let activeReminder: SharedTrackedDepartureReminder?
    let stopTrackingDeparture: () -> Void
    let cancelDepartureReminder: () -> Void

    var body: some View {
        if trackedDeparture != nil || activeReminder != nil {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let trackedDeparture {
                HStack(alignment: .top, spacing: 10) {
                    Label(
                        "Live Activity tracking \(trackedDeparture.lineName) to \(trackedDeparture.destination)",
                        systemImage: "livephoto"
                    )
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Stop", action: stopTrackingDeparture)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }

            if let activeReminder {
                HStack(alignment: .top, spacing: 10) {
                    Label(
                        "Reminder set for \(activeReminder.leadTimeMinutes) min before \(activeReminder.lineName) to \(activeReminder.destination)",
                        systemImage: "bell.badge.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Cancel", action: cancelDepartureReminder)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
