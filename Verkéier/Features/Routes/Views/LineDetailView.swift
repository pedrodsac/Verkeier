import SwiftUI

struct LineDetailView: View {
    let viewModel: LineDetailPresentationModel
    let actions: LineDetailActions

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                List {
                if detail.directions.count > 1 {
                    Picker(
                        "Direction",
                        selection: Binding(
                            get: { detail.selectedDirectionID },
                            set: actions.selectDirection
                        )
                    ) {
                        ForEach(detail.directions) { direction in
                            Text(direction.title).tag(direction.id)
                        }
                    }
                    .pickerStyle(.inline)
                }

                    Section("Stop Sequence") {
                        ForEach(Array(detail.stopSequence.enumerated()), id: \.element.id) { index, stop in
                        let destinationStop = Stop(
                            id: stop.id,
                            name: stop.name,
                            location: stop.location,
                            modes: [detail.route.mode],
                            dataSource: .gtfs
                        )
                        NavigationLink(value: TransitSheetRoute.stopDetail(destinationStop)) {
                            HStack(alignment: .center, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let platform = stop.platform {
                                        Text("Platform \(platform)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !viewModel.alerts.isEmpty {
                    Section("Disruption Impact") {
                        ForEach(viewModel.alerts.prefix(3)) { alert in
                            LineAlertRow(alert: alert)
                        }
                    }
                }

                if !detail.upcomingDepartures.isEmpty {
                    Section("Upcoming Timetable") {
                        ForEach(detail.upcomingDepartures) { departure in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(departure.departureTime, style: .time)
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(departure.destinationName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("From \(departure.originName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
                .listStyle(.insetGrouped)
            } else if let route = viewModel.route {
                CompactUnavailableCard(
                    title: "Line details unavailable",
                    message: viewModel.errorMessage ?? "No GTFS timetable details are available for \(route.shortName).",
                    systemImage: "tram.fill"
                )
            } else {
                CompactUnavailableCard(
                    title: "No line selected",
                    message: "Choose a line from stop detail to open its timetable and stop sequence.",
                    systemImage: "tram.fill"
                )
            }
        }
        .refreshable { await actions.refresh() }
    }
}

private struct LineAlertRow: View {
    let alert: AlertMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
            Text(alert.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
