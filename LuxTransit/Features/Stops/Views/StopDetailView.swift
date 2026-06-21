import SwiftUI

struct StopDetailView: View {
    let viewModel: StopDetailPresentationModel
    let openDirections: () -> Void
    let trackDeparture: (Departure) -> Void
    let toggleDepartureLine: (TransitRoute) -> Void
    let showLineDetail: (TransitRoute) -> Void
    let selectDeparturePlatform: (String?) -> Void

    var body: some View {
        if let stop = viewModel.stop {
            VStack(alignment: .leading, spacing: 16) {
                PlatformFilterPicker(
                    platforms: viewModel.availablePlatforms,
                    selectedPlatform: viewModel.selectedPlatform,
                    selectPlatform: selectDeparturePlatform
                )

                StopDetailHeader(
                    stop: stop,
                    routes: viewModel.routes,
                    selectedLine: viewModel.selectedLine,
                    openDirections: openDirections,
                    toggleDepartureLine: toggleDepartureLine,
                    showLineDetail: showLineDetail
                )

                if let liveActivityErrorMessage = viewModel.liveActivityErrorMessage {
                    Label(liveActivityErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            .orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                DepartureBoardView(
                    departures: viewModel.departures,
                    isLoading: viewModel.isLoadingDepartures,
                    errorMessage: viewModel.errorMessage,
                    lastUpdated: viewModel.lastUpdated,
                    isStale: viewModel.isStale,
                    trackedDepartureId: viewModel.trackedDepartureId,
                    trackDeparture: trackDeparture
                )

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
}

private struct OfflineScheduleSection: View {
    let departures: [OfflineScheduleDeparture]

    var body: some View {
        if !departures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scheduled from GTFS")
                    .font(.headline.weight(.semibold))
                Text("Offline timetable preview when live ATP departures are missing or delayed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(departures) { departure in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        RouteChip(
                            route: TransitRoute(
                                id: departure.id,
                                shortName: departure.lineName,
                                mode: departure.mode,
                                dataSource: .gtfs
                            )
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(departure.destination)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if let platform = departure.platform, !platform.isEmpty {
                                Text("Platform \(platform)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(departure.departureDate, style: .time)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct StopDetailHeader: View {
    let stop: Stop
    let routes: [TransitRoute]
    let selectedLine: String?
    let openDirections: () -> Void
    let toggleDepartureLine: (TransitRoute) -> Void
    let showLineDetail: (TransitRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StopMetadataPanel(
                routes: routes,
                selectedLine: selectedLine,
                toggleDepartureLine: toggleDepartureLine,
                showLineDetail: showLineDetail
            )

            DirectionsButton(openDirections: openDirections)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for stop: Stop) -> String {
        if stop.modes.contains(.train) { return "train.side.front.car" }
        if stop.modes.contains(.tram) { return "tram.fill" }
        if stop.modes.contains(.funicular) { return "cablecar.fill" }
        return "bus.fill"
    }

    private func color(for stop: Stop) -> Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return .blue
    }
}

private struct PlatformFilterPicker: View {
    let platforms: [String]
    let selectedPlatform: String?
    let selectPlatform: (String?) -> Void

    var body: some View {
        if !platforms.isEmpty {
            Picker(
                "Platform",
                selection: Binding(
                    get: { selectedPlatform ?? "" },
                    set: { selectPlatform($0.isEmpty ? nil : $0) }
                )
            ) {
                Text("All").tag("")
                ForEach(platforms, id: \.self) { platform in
                    Text(platform).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Platform filter")
        }
    }
}

private struct DirectionsButton: View {
    let openDirections: () -> Void

    var body: some View {
        Button(action: openDirections) {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.blue, in: Capsule())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get directions")
    }
}

private struct StopMetadataPanel: View {
    let routes: [TransitRoute]
    let selectedLine: String?
    let toggleDepartureLine: (TransitRoute) -> Void
    let showLineDetail: (TransitRoute) -> Void

    @ViewBuilder
    var body: some View {
        if !routes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routes.prefix(16)) { route in
                        RouteLineCard(
                            route: route,
                            isSelected: route.id == selectedLine,
                            toggleDepartureLine: { toggleDepartureLine(route) },
                            showLineDetail: { showLineDetail(route) }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

}

private struct RouteLineCard: View {
    let route: TransitRoute
    let isSelected: Bool
    let toggleDepartureLine: () -> Void
    let showLineDetail: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleDepartureLine) {
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .accessibilityHidden(true)
                    Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                    }
                }
                .font(.callout.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(routeColor.opacity(isSelected ? 0.20 : 0.14), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        routeColor.opacity(isSelected ? 0.55 : 0.25),
                        lineWidth: isSelected ? 1.1 : 0.7
                    )
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            Button(action: showLineDetail) {
                Image(systemName: "info.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(routeColor)
                    .frame(width: 28, height: 28)
                    .background(.background.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show line details for \(route.shortName.isEmpty ? route.mode.displayName : route.shortName)")
        }
    }

    init(
        route: TransitRoute,
        isSelected: Bool = false,
        toggleDepartureLine: @escaping () -> Void = {},
        showLineDetail: @escaping () -> Void = {}
    ) {
        self.route = route
        self.isSelected = isSelected
        self.toggleDepartureLine = toggleDepartureLine
        self.showLineDetail = showLineDetail
    }

    private var iconName: String {
        switch route.mode {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .walking: "figure.walk"
        case .unknown: "circle"
        }
    }

    private var routeColor: Color {
        switch route.mode {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .walking, .unknown: .secondary
        }
    }
}

private struct RouteChip: View {
    let route: TransitRoute
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                .lineLimit(1)
        }
        .font(.callout.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(routeColor.opacity(isSelected ? 0.20 : 0.14), in: Capsule())
        .overlay {
            Capsule().stroke(
                routeColor.opacity(isSelected ? 0.55 : 0.25),
                lineWidth: isSelected ? 1.1 : 0.7
            )
        }
    }

    private var iconName: String {
        switch route.mode {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .walking: "figure.walk"
        case .unknown: "circle"
        }
    }

    private var routeColor: Color {
        switch route.mode {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .walking, .unknown: .secondary
        }
    }
}

private struct StopDisruptionSection: View {
    let alerts: [AlertMessage]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Disruption Impact")
                    .font(.headline.weight(.semibold))
                Text("These AVL alerts affect this stop or its served lines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(alerts.prefix(3)) { alert in
                    CompactAlertRow(alert: alert)
                }
            }
        }
    }
}

private struct CompactAlertRow: View {
    let alert: AlertMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
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

struct DepartureBoardView: View {
    let departures: [Departure]
    let isLoading: Bool
    let errorMessage: String?
    let lastUpdated: Date?
    let isStale: Bool
    let trackedDepartureId: String?
    let trackDeparture: (Departure) -> Void

    var body: some View {
        if isLoading && departures.isEmpty {
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
            VStack(alignment: .leading, spacing: 8) {
                DepartureBoardStatus(lastUpdated: lastUpdated, isStale: isStale)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(departures) { departure in
                            DepartureListRow(
                                departure: departure,
                                isTracked: departure.id == trackedDepartureId,
                                trackDeparture: { trackDeparture(departure) }
                            )
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
    }
}

struct DepartureBoardStatus: View {
    let lastUpdated: Date?
    let isStale: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isStale ? .orange : .green)
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

private struct DepartureTimingStatus: View {
    let countdownText: String
    let countdownColor: Color
    let statusBadge: String?
    let statusColor: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(countdownText)
                .font(.headline.weight(.bold))
                .foregroundStyle(countdownColor)
                .lineLimit(1)
                .contentTransition(.numericText())

            if let statusBadge {
                HStack(spacing: 4) {
                    if statusBadge == "On time" {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    }
                    Text(statusBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(minWidth: 50, alignment: .trailing)
    }
}

struct DepartureListRow: View {
    let departure: Departure
    var isTracked: Bool = false
    var showsTrackButton: Bool = true
    var trackDeparture: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: transportIcon)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(departure.lineName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 52, minHeight: 34)
            .padding(.horizontal, 7)
            .background(
                lineColor.gradient,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(departure.destination)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(departureTimeText)
                    if let platform = departure.platform {
                        Text("Platform \(platform)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
			.frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            DepartureTimingStatus(
                countdownText: countdownText,
                countdownColor: countdownColor,
                statusBadge: statusBadge,
                statusColor: statusColor
            )

            if showsTrackButton {
                Button(action: trackDeparture) {
                    Image(systemName: isTracked ? "timer.circle.fill" : "timer")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isTracked ? .blue : .secondary)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.separator.opacity(0.20), lineWidth: 0.7)
                        }
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .disabled(isTracked)
                .accessibilityLabel(isTracked ? "Tracking departure" : "Track departure")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            .background.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.16), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var departureDate: Date? {
        departure.realtimeDeparture ?? departure.scheduledDeparture
    }

    private var departureTimeText: String {
        departureDate?.formatted(date: .omitted, time: .shortened) ?? "Time unknown"
    }

    private var countdownText: String {
        guard let departureDate else { return "—" }
        let minutes = Int(departureDate.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Now" }
        if minutes < 90 { return "\(minutes)m" }
        return departureDate.formatted(date: .omitted, time: .shortened)
    }

    private var statusBadge: String? {
        switch departure.status {
        case .cancelled: "Cancelled"
        case .delayed(let minutes): "+\(minutes)m"
        case .onTime: "On time"
        case .scheduled, .unknown: nil
        }
    }

    private var countdownColor: Color {
        switch departure.status {
        case .cancelled: .red
        case .delayed: .orange
        default: .primary
        }
    }

    private var statusColor: Color {
        switch departure.status {
        case .delayed: .orange
        case .cancelled: .red
        case .onTime: .green
        case .scheduled, .unknown: .secondary
        }
    }

    private var lineColor: Color {
        switch transportKind {
        case .tram: .orange
        case .train: .red
        case .bus: .blue
        }
    }

    private var transportIcon: String {
        switch transportKind {
        case .tram: "tram.fill"
        case .train: "train.side.front.car"
        case .bus: "bus.fill"
        }
    }

    private var transportKind: DepartureTransportKind {
        let line = departure.lineName.uppercased()
        if line.hasPrefix("T") { return .tram }
        if line.hasPrefix("R") || line.hasPrefix("RE") || line.hasPrefix("IC") { return .train }
        return .bus
    }
}

private enum DepartureTransportKind {
    case bus
    case tram
    case train
}

struct DepartureLoadingCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CompactUnavailableCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.secondary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureLoadingCard(title: "Loading departures")
}

#Preview(traits: .sizeThatFitsLayout) {
    CompactUnavailableCard(
        title: "No departures",
        message: "No live departures are available for this stop.",
        systemImage: "clock.badge.exclamationmark"
    )
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureBoardStatus(lastUpdated: .now, isStale: false)
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureBoardStatus(lastUpdated: .now.addingTimeInterval(-600), isStale: true)
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureListRow(
        departure: Departure(
            id: "dep-1",
            stopId: "200209001",
            lineName: "16",
            destination: "Kirchberg",
            scheduledDeparture: .now.addingTimeInterval(300),
            realtimeDeparture: .now.addingTimeInterval(420),
            delayMinutes: 2,
            platform: "1",
            dataSource: .mock
        )
    )
    .padding(.horizontal, 12)
}

#Preview(traits: .sizeThatFitsLayout) {
    RouteChip(
        route: TransitRoute(
            id: "route-1",
            shortName: "16",
            longName: "Luxembourg – Kirchberg",
            mode: .bus,
            dataSource: .mock
        ),
        isSelected: false
    )
}

#Preview(traits: .sizeThatFitsLayout) {
    RouteChip(
        route: TransitRoute(
            id: "route-2",
            shortName: "T1",
            longName: "Luxembourg Gare – Stadion",
            mode: .tram,
            dataSource: .mock
        ),
        isSelected: true
    )
}
