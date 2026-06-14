import SwiftUI

struct StopDetailView: View {
    let viewModel: StopDetailPresentationModel
    let openDirections: () -> Void
    let trackDeparture: (Departure) -> Void

    var body: some View {
        if let stop = viewModel.stop {
            VStack(alignment: .leading, spacing: 16) {
                StopDetailHeader(
                    stop: stop,
                    routes: viewModel.routes,
                    openDirections: openDirections
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

private struct StopDetailHeader: View {
    let stop: Stop
    let routes: [TransitRoute]
    let openDirections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName(for: stop))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color(for: stop).gradient, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.locality ?? stop.dataSource.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            StopMetadataPanel(routes: routes)

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

    @ViewBuilder
    var body: some View {
        if !routes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routes.prefix(16)) { route in
                        RouteChip(route: route)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

}

private struct RouteChip: View {
    let route: TransitRoute

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(route.shortName.isEmpty ? route.mode.displayName : route.shortName)
                .lineLimit(1)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(routeColor.opacity(0.14), in: Capsule())
        .overlay {
            Capsule().stroke(routeColor.opacity(0.25), lineWidth: 0.7)
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

            Spacer(minLength: 6)

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
