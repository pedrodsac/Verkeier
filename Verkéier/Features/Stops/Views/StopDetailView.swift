import SwiftUI

struct StopDetailView: View {
    let viewModel: StopDetailPresentationModel
    let actions: StopDetailActions

    var body: some View {
        if let stop = viewModel.stop {
            VStack(alignment: .leading, spacing: 16) {
                DepartureBoardAdvancedFilterMenu(
                    filter: viewModel.departureBoardFilter,
                    update: actions.updateDepartureBoardFilter
                )

                PlatformFilterPicker(
                    platforms: viewModel.availablePlatforms,
                    selectedPlatform: viewModel.selectedPlatform,
                    selectPlatform: actions.selectDeparturePlatform
                )

                StopDetailHeader(
                    stop: stop,
                    routes: viewModel.routes,
                    selectedLine: viewModel.selectedLine,
                    toggleDepartureLine: actions.toggleDepartureLine
                )

                if !viewModel.mergedDepartures.isEmpty {
                    ShareLink(
                        item: stopDeparturesShareText(stop: stop, departures: viewModel.mergedDepartures)
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
        lines.append("via Verkéier")
        return lines.joined(separator: "\n")
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
