import SwiftUI

/// A line's stop sequence and upcoming timetable, in one direction.
struct LineDetailScreen: View {
    @Environment(LineDetailModel.self) private var model
    @Environment(AlertsModel.self) private var alerts
    @Environment(SheetRouter.self) private var router
    @Environment(\.gtfsService) private var gtfsService

    let route: TransitRoute

    var body: some View {
        Group {
            if let detail = model.selectedLineDetail {
                List {
                    if detail.directions.count > 1 {
                        Picker(
                            "Direction",
                            selection: Binding(
                                get: { detail.selectedDirectionID },
                                set: selectDirection
                            )
                        ) {
                            ForEach(detail.directions) { direction in
                                Text(direction.title.stationDisplayName(hidingLocality: detail.route.mode == .tram))
                                    .tag(direction.id)
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
                            NavigationLink(value: SheetRoute.stopDetail(destinationStop)) {
                                HStack(alignment: .center, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name.stationDisplayName(hidingLocality: detail.route.mode == .tram))
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

                    let lineAlerts = alerts.alerts(forLine: model.selectedLineDetailRoute, detail: detail)
                    if !lineAlerts.isEmpty {
                        Section("Disruption Impact") {
                            ForEach(lineAlerts.prefix(3)) { alert in
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
                                        Text(
                                            departure.destinationName.stationDisplayName(
                                                hidingLocality: detail.route.mode == .tram
                                            )
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        Text(
                                            "From \(departure.originName.stationDisplayName(hidingLocality: detail.route.mode == .tram))"
                                        )
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
            } else if let route = model.selectedLineDetailRoute {
                CompactUnavailableCard(
                    title: "Line details unavailable",
                    message: model.selectedLineDetailErrorMessage
                        ?? "No GTFS timetable details are available for \(route.shortName).",
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
        .refreshable { await router.refreshLineDetail() }
        .navigationTitle(route.shortName.isEmpty ? "Line details" : route.shortName)
        .toolbarTitleDisplayMode(.inline)
    }

    private func selectDirection(_ directionID: String) {
        model.selectLineDetailDirection(directionID)
        Task { await model.loadLineDetail(using: gtfsService) }
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
