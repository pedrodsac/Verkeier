import SwiftUI

struct DepartureBoardView: View {
    let viewModel: StopDetailPresentationModel
    let actions: StopDetailActions

    private var departures: [Departure] {
        viewModel.departures
    }

    private var isLoading: Bool {
        viewModel.isLoadingDepartures
    }

    private var errorMessage: String? {
        viewModel.errorMessage
    }

    private var trackedDepartureId: String? {
        viewModel.trackedDepartureId
    }

    private var activeReminder: SharedTrackedDepartureReminder? {
        viewModel.activeReminder
    }

    var body: some View {
        if isLoading, departures.isEmpty {
            DepartureLoadingCard(title: "Loading departures")
        } else if let errorMessage {
            CompactUnavailableCard(
                title: "Departures unavailable",
                message: errorMessage,
                systemImage: "wifi.exclamationmark"
            )
        } else if departures.isEmpty {
            CompactUnavailableCard(
                title: "No departures",
                message: "No live departures are available for this stop.",
                systemImage: "clock.badge.exclamationmark"
            )
        } else {
            let trackedDeparture = departures.first(where: { $0.id == trackedDepartureId })
            let showsTrackingCard = trackedDeparture != nil || activeReminder != nil
            let lastOfDayIDs = lastServiceDepartureIDs(in: departures)

            VStack(alignment: .leading, spacing: 8) {
                DepartureTrackingStatusCard(
                    trackedDeparture: trackedDeparture,
                    activeReminder: activeReminder,
                    stopTrackingDeparture: actions.stopTrackingDeparture,
                    cancelDepartureReminder: actions.cancelDepartureReminder
                )

                // Hero card for the next ride — hidden while a tracking card is shown.
                if !showsTrackingCard,
                   let next = departures.first(where: { !$0.isCancelled }) {
                    NextDepartureHeroCard(departure: next)
                }

                let now = Date()
                let departed = departures
                    .filter { ($0.realtimeDeparture ?? $0.scheduledDeparture).map { $0 < now } ?? false }
                    .suffix(3)
                let upcoming = departures
                    .filter { ($0.realtimeDeparture ?? $0.scheduledDeparture).map { $0 >= now } ?? true }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !departed.isEmpty {
                            DisclosureGroup("Recently departed") {
                                ForEach(Array(departed)) { departure in
                                    DepartureListRow(departure: departure, showsControls: false)
                                        .opacity(0.55)
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .tint(.secondary)
                        }

                        ForEach(upcoming) { departure in
                            DepartureListRow(
                                departure: departure,
                                isTracked: departure.id == trackedDepartureId,
                                isLastOfDay: lastOfDayIDs.contains(departure.id),
                                activeReminder: activeReminder,
                                startTrackingDeparture: { actions.startTrackingDeparture(departure) },
                                stopTrackingDeparture: actions.stopTrackingDeparture,
                                scheduleReminder: { minutes in
                                    actions.scheduleDepartureReminder(departure, minutes)
                                },
                                cancelReminder: actions.cancelDepartureReminder
                            )
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
    }
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

struct DepartureBoardStatus: View {
    let lastUpdated: Date?
    let isStale: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isStale ? .orange : .green)
                .contentTransition(.symbolEffect(.replace))
                .animation(Animation.respectingReduceMotion(.snappy, reduceMotion), value: isStale)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        guard let lastUpdated else { return "Not updated yet" }
        let formatted = lastUpdated.formatted(date: .omitted, time: .shortened)
        return isStale ? "Stale · updated \(formatted)" : "Updated \(formatted)"
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureBoardStatus(lastUpdated: .now, isStale: false)
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureBoardStatus(lastUpdated: .now.addingTimeInterval(-600), isStale: true)
}
