import SwiftData
import SwiftUI

/// The live departure board for one stop.
struct StopDetailView: View {
    @Environment(StopDetailModel.self) private var model
    @Environment(AlertsModel.self) private var alerts
    @Environment(FavouritesModel.self) private var favourites
    @Environment(SheetRouter.self) private var router
    @Environment(\.liveTransitService) private var liveTransitService
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.liveActivityManager) private var liveActivityManager
    @Environment(\.departureReminderService) private var departureReminderService
    @Environment(\.modelContext) private var modelContext

    let stop: Stop

    @State private var favouriteCustomization: FavouriteCustomizationDraft?

    var body: some View {
        List {
            if let selectedStop = model.selectedStop {
                board(for: selectedStop)
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
        .navigationTitle(stop.displayName)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $favouriteCustomization) { draft in
            FavouriteCustomizerView(
                stop: draft.stop,
                initialLabel: draft.label,
                initialColorHex: draft.colorHex,
                initialIconName: draft.iconName
            ) { label, colorHex, iconName in
                favourites.save(
                    draft.stop,
                    label: label,
                    colorHex: colorHex,
                    iconName: iconName,
                    boardFilter: model.departureBoardFilter,
                    in: modelContext
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .refreshable { await refresh() }
        .task(id: model.selectedStop?.id) { await keepBoardCurrent() }
        // Haptic + VoiceOver feedback when the board refreshes with new data.
        .sensoryFeedback(.impact(weight: .light), trigger: model.departuresLastUpdated)
        .onChange(of: model.departuresLastUpdated) { _, newValue in
            if newValue != nil {
                AccessibilityNotification.Announcement("Departures updated").post()
            }
        }
    }
}

// MARK: - Subviews

private extension StopDetailView {
    @ViewBuilder
    func board(for selectedStop: Stop) -> some View {
        StopDetailHeader(
            stop: selectedStop,
            routes: model.selectedStopRoutes,
            selectedLine: model.selectedDepartureLine,
            showDirections: router.showDirections,
            toggleDepartureLine: toggleDepartureLine,
            availablePlatforms: model.availablePlatforms,
            selectedPlatform: model.selectedDeparturePlatform,
            selectDeparturePlatform: selectDeparturePlatform
        )
        .listRowInsets(chipsRowInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .safeAreaPadding(.horizontal, 16)

        if let liveActivityErrorMessage = liveActivityManager.lastErrorMessage {
            warningRow(liveActivityErrorMessage, systemImage: "exclamationmark.triangle.fill")
        }

        if let departureReminderErrorMessage = departureReminderService.lastErrorMessage {
            warningRow(departureReminderErrorMessage, systemImage: "bell.badge.fill")
        }

        departures(at: selectedStop)

        let stopAlerts = alerts.alerts(forStop: selectedStop, routes: model.selectedStopRoutes)
        if !stopAlerts.isEmpty {
            StopDisruptionSection(alerts: stopAlerts)
                .listRowInsets(cardRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    func departures(at selectedStop: Stop) -> some View {
        let departures = model.displayedDepartures
        if model.isLoadingDepartures, departures.isEmpty {
            DepartureLoadingCard(title: "Loading departures")
                .listRowInsets(cardRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if departures.isEmpty {
            CompactUnavailableCard(
                title: model.departuresErrorMessage == nil ? "No departures" : "Departures unavailable",
                message: model.departuresErrorMessage ?? "No live departures are available for this stop.",
                systemImage: model.departuresErrorMessage == nil ? "clock.badge.exclamationmark" : "wifi.exclamationmark"
            )
            .listRowInsets(cardRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            let lastOfDayIDs = lastServiceDepartureIDs(in: departures)
            let trackedDepartureId = liveActivityManager.trackedDepartureId
            let trackedDeparture = departures.first { $0.id == trackedDepartureId }

            if model.isShowingScheduledFallback {
                Label("Live updates unavailable · showing timetable", systemImage: "wifi.exclamationmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .listRowInsets(actionRowInsets)
                    .listRowBackground(Color.orange.opacity(0.12))
                    .listRowSeparator(.hidden)
            }

            if trackedDeparture != nil || activeReminder != nil {
                DepartureTrackingStatusCard(
                    trackedDeparture: trackedDeparture,
                    activeReminder: activeReminder,
                    stopTrackingDeparture: stopTrackingDeparture,
                    cancelDepartureReminder: departureReminderService.cancelReminder
                )
                .listRowInsets(cardRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(model.departedDepartures, id: \.id) { departure in
                DepartureListRow(departure: departure, showsControls: false)
                    .background { courseLink(for: departure, at: selectedStop) }
                    .opacity(0.55)
                    .listRowInsets(departureRowInsets)
            }

            ForEach(model.upcomingDepartures, id: \.id) { departure in
                DepartureListRow(
                    departure: departure,
                    isTracked: departure.id == trackedDepartureId,
                    isLastOfDay: lastOfDayIDs.contains(departure.id),
                    showsControls: departure.dataSource != .gtfs,
                    activeReminder: activeReminder,
                    startTrackingDeparture: { startTracking(departure) },
                    stopTrackingDeparture: stopTrackingDeparture,
                    scheduleReminder: { minutes in scheduleReminder(for: departure, leadTimeMinutes: minutes) },
                    cancelReminder: departureReminderService.cancelReminder
                )
                .background { courseLink(for: departure, at: selectedStop) }
                .listRowInsets(departureRowInsets)
            }
        }
    }

    func courseLink(for departure: Departure, at selectedStop: Stop) -> some View {
        NavigationLink(value: TransitSheetRoute.departureTrip(departure, selectedStop)) { EmptyView() }
            .opacity(0)
            .accessibilityLabel("View full course for \(departure.lineName) to \(departure.displayDestination)")
    }

    func warningRow(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.orange)
            .listRowInsets(actionRowInsets)
            .listRowBackground(Color.orange.opacity(0.12))
            .listRowSeparator(.hidden)
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if let shareText = model.departuresShareText {
            ToolbarTitleMenu {
                ShareLink(item: shareText) {
                    Label("Share next departures", systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            let isFavourite = model.selectedStop.map(favourites.isFavourite) ?? false
            Button {
                toggleFavourite(isFavourite: isFavourite)
            } label: {
                Label(
                    isFavourite ? "Remove favourite" : "Save favourite",
                    systemImage: isFavourite ? "star.fill" : "star"
                )
            }
            .tint(isFavourite ? .yellow : nil)
        }
    }

    var chipsRowInsets: EdgeInsets { EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0) }
    var actionRowInsets: EdgeInsets { EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16) }
    var cardRowInsets: EdgeInsets { EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16) }
    var departureRowInsets: EdgeInsets { EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16) }
}

// MARK: - Actions

private extension StopDetailView {
    var activeReminder: SharedTrackedDepartureReminder? {
        guard let reminder = departureReminderService.activeReminder,
            reminder.stopId == model.selectedStop?.id
        else { return nil }
        return reminder
    }

    func refresh() async {
        await model.refresh(
            using: liveTransitService,
            gtfsService: gtfsService,
            liveActivityManager: liveActivityManager,
            departureReminderService: departureReminderService
        )
    }

    /// Refreshes the board now and every 45 seconds while it is on screen.
    func keepBoardCurrent() async {
        guard model.selectedStop != nil else { return }
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func toggleDepartureLine(_ route: TransitRoute) {
        model.toggleDepartureLine(route)
        Task { await model.loadDepartures(using: liveTransitService, gtfsService: gtfsService) }
    }

    func selectDeparturePlatform(_ platform: String?) {
        model.selectDeparturePlatform(platform)
        Task { await model.loadDepartures(using: liveTransitService, gtfsService: gtfsService) }
    }

    func toggleFavourite(isFavourite: Bool) {
        guard let selectedStop = model.selectedStop else { return }
        if isFavourite {
            favourites.remove(stopID: selectedStop.id, in: modelContext)
        } else {
            favouriteCustomization = FavouriteCustomizationDraft(stop: selectedStop)
        }
    }

    func startTracking(_ departure: Departure) {
        guard let selectedStop = model.selectedStop else { return }
        Task { await liveActivityManager.startTracking(departure: departure, stop: selectedStop) }
    }

    func stopTrackingDeparture() {
        Task { await liveActivityManager.endTracking() }
    }

    func scheduleReminder(for departure: Departure, leadTimeMinutes: Int) {
        guard let selectedStop = model.selectedStop else { return }
        Task {
            await departureReminderService.scheduleReminder(
                for: departure,
                stop: selectedStop,
                leadTimeMinutes: leadTimeMinutes
            )
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
            existingTime >= departureTime
        {
            continue
        }
        latestByLine[departure.lineName] = departure
    }

    return Set(
        latestByLine.values.compactMap { departure in
            guard let departureTime = time(departure),
                calendar.component(.hour, from: departureTime) >= 18
            else { return nil }
            return departure.id
        }
    )
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
