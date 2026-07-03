import SwiftUI

struct LineDetailView: View {
    let viewModel: LineDetailPresentationModel
    let actions: LineDetailActions

    var body: some View {
        if let detail = viewModel.detail {
            VStack(alignment: .leading, spacing: 16) {
                header(detail.route)

                if !viewModel.alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Disruption Impact")
                            .font(.headline.weight(.semibold))
                        ForEach(viewModel.alerts.prefix(3)) { alert in
                            LineAlertRow(alert: alert)
                        }
                    }
                }

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
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Stop Sequence")
                        .font(.headline.weight(.semibold))
                    Text(detail.serviceSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(Array(detail.stopSequence.enumerated()), id: \.element.id) { index, stop in
                        Button {
                            actions.selectStop(
                                Stop(
                                    id: stop.id,
                                    name: stop.name,
                                    location: stop.location,
                                    modes: [detail.route.mode],
                                    dataSource: .gtfs
                                )
                            )
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !detail.upcomingDepartures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upcoming Timetable")
                            .font(.headline.weight(.semibold))
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
                            .padding(.vertical, 6)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func header(_ route: TransitRoute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(lineColor(for: route).gradient, in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.longName ?? route.shortName)
                        .font(.headline.weight(.semibold))
                    if let operatorName = route.operatorName {
                        Text(operatorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func lineColor(for route: TransitRoute) -> Color {
        switch route.mode {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .teal
        case .walking, .unknown: .secondary
        }
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
