import SwiftUI

struct StopDetailView: View {
    let viewModel: StopDetailPresentationModel
    let actions: StopDetailActions

    var body: some View {
        if let stop = viewModel.stop {
            VStack(alignment: .leading, spacing: 16) {
                PlatformFilterPicker(
                    platforms: viewModel.availablePlatforms,
                    selectedPlatform: viewModel.selectedPlatform,
                    selectPlatform: actions.selectDeparturePlatform
                )

                StopDetailHeader(
                    stop: stop,
                    routes: viewModel.routes,
                    selectedLine: viewModel.selectedLine,
                    openDirections: actions.openDirections,
                    toggleDepartureLine: actions.toggleDepartureLine,
                    showLineDetail: actions.showLineDetail
                )

                if !viewModel.departures.isEmpty {
                    ShareLink(
                        item: stopDeparturesShareText(stop: stop, departures: viewModel.departures)
                    ) {
                        Label("Share next departures", systemImage: "square.and.arrow.up")
                            .font(.callout.weight(.medium))
                    }
                }

                if let liveActivityErrorMessage = viewModel.liveActivityErrorMessage {
                    Label(liveActivityErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            .orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }

                if let departureReminderErrorMessage = viewModel.departureReminderErrorMessage {
                    Label(departureReminderErrorMessage, systemImage: "bell.badge.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            .orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }

                DepartureBoardView(viewModel: viewModel, actions: actions)
                    // Haptic + VoiceOver feedback when the board refreshes with new data.
                    .sensoryFeedback(.impact(weight: .light), trigger: viewModel.lastUpdated)
                    .onChange(of: viewModel.lastUpdated) { _, newValue in
                        if newValue != nil {
                            AccessibilityNotification.Announcement("Departures updated").post()
                        }
                    }

                StopDisruptionSection(alerts: viewModel.alerts)

                OfflineScheduleSection(departures: viewModel.offlineScheduledDepartures)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            CompactUnavailableCard(
                title: "No stop selected",
                message: "Choose a marker, favourite, nearby stop, or search result.",
                systemImage: "bus"
            )
        }
    }

    /// Formats the next five departures as a shareable plain-text message.
    private func stopDeparturesShareText(stop: Stop, departures: [Departure]) -> String {
        var lines = ["Next departures — \(stop.name)"]
        for departure in departures.prefix(5) {
            let time = (departure.realtimeDeparture ?? departure.scheduledDeparture)?
                .formatted(date: .omitted, time: .shortened) ?? "--:--"
            let status = if departure.isCancelled {
                " (cancelled)"
            } else if let delay = departure.delayMinutes, delay > 0 {
                " (+\(delay) min)"
            } else {
                ""
            }
            lines.append("\(time)  \(departure.lineName) → \(departure.destination)\(status)")
        }
        lines.append("via LuxTransit")
        return lines.joined(separator: "\n")
    }
}
