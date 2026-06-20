import SwiftUI

struct RouteView: View {
    let viewModel: RoutePresentationModel
    let calculateRoute: () -> Void
    let selectRouteOption: (String) -> Void
    let showMoreRouteOptions: () -> Void
    let openInAppleMaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isWaitingForLocation {
                DepartureLoadingCard(title: "Waiting for current location")
            } else if viewModel.isCalculating, viewModel.routeOptions.isEmpty {
                DepartureLoadingCard(title: "Finding public transport routes")
            } else if viewModel.isCalculating {
                RouteInfoBanner(
                    title: "Refreshing public transport routes",
                    systemImage: "arrow.trianglehead.clockwise"
                )
            }

            if let errorMessage = viewModel.errorMessage {
                CompactUnavailableCard(
                    title: "Public transport route unavailable",
                    message: errorMessage,
                    systemImage: "tram.fill"
                )
            } else if !viewModel.isCalculating && !viewModel.isWaitingForLocation && viewModel.routeOptions.isEmpty {
                CompactUnavailableCard(
                    title: "No route selected",
                    message: "Choose a stop and directions will show public transport options from your current location.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }

            if let statusMessage = viewModel.statusMessage {
                RouteStatusMessage(text: statusMessage)
            }

            if !viewModel.routeOptions.isEmpty {
                RouteOptionsSection(
                    options: viewModel.visibleRouteOptions,
                    selectedRouteOptionID: viewModel.selectedRouteOptionID,
                    selectRouteOption: selectRouteOption,
                    showMoreRouteOptions: showMoreRouteOptions
                )
            }

            actionRow

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Group {
            if let selectedStop = viewModel.selectedStop {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directions")
                        .font(.headline.weight(.semibold))
                    Text("To \(selectedStop.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose a stop from the map, favourites, nearby suggestions, or search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: calculateRoute) {
                Label(
                    calculateButtonTitle,
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                viewModel.selectedStop == nil
                    || viewModel.isCalculating
                    || viewModel.isWaitingForLocation
            )

            Button(action: openInAppleMaps) {
                Label("Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.selectedStop == nil)
        }
    }

    private var calculateButtonTitle: String {
        if viewModel.isWaitingForLocation { return "Waiting" }
        if viewModel.isCalculating { return "Finding" }
        return viewModel.routeOptions.isEmpty ? "Find Routes" : "Refresh"
    }
}

private struct RouteOptionsSection: View {
    let options: [RouteOption]
    let selectedRouteOptionID: String?
    let selectRouteOption: (String) -> Void
    let showMoreRouteOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route options")
                .font(.headline.weight(.semibold))

            ForEach(options) { option in
                RouteOptionCard(
                    option: option,
                    isSelected: option.id == selectedRouteOptionID,
                    selectRouteOption: { selectRouteOption(option.id) }
                )
            }

            Button(action: showMoreRouteOptions) {
                Label("Show 3 more", systemImage: "plus.circle")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

struct RouteTimelineView: View {
    let viewModel: RoutePresentationModel
    let openInAppleMaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let selectedOption = viewModel.selectedRouteOption {
                RouteLegList(legs: selectedOption.plan.legs)
            } else {
                CompactUnavailableCard(
                    title: "No selected route",
                    message: "Choose a route option to see its timeline.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }

            Button(action: openInAppleMaps) {
                Label("Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.selectedStop == nil)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Directions")
                .font(.headline.weight(.semibold))

            if let selectedStop = viewModel.selectedStop {
                Text("To \(selectedStop.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RouteOptionCard: View {
    let option: RouteOption
    let isSelected: Bool
    let selectRouteOption: () -> Void

    var body: some View {
        Button(action: selectRouteOption) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(iconColor.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timeRangeText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        RouteOptionBadge(status: option.status(at: .now))
                    }

                    Text(primarySummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(secondarySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(cardStroke, lineWidth: isSelected ? 1.2 : 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Opens route timeline")
    }

    private var iconName: String {
        switch option.transitLegs.first?.mode ?? .unknown {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .walking: "figure.walk"
        case .unknown: "arrow.triangle.branch"
        }
    }

    private var iconColor: Color {
        switch option.transitLegs.first?.mode ?? .unknown {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .walking, .unknown: .secondary
        }
    }

    private var timeRangeText: String {
        let departure = option.firstTransitDepartureTime
        let arrival = option.arrivalTime

        switch (departure, arrival) {
        case let (.some(departure), .some(arrival)):
            return "\(departure.formatted(date: .omitted, time: .shortened))-\(arrival.formatted(date: .omitted, time: .shortened))"
        case let (.some(departure), .none):
            return departure.formatted(date: .omitted, time: .shortened)
        default:
            return "Scheduled route"
        }
    }

    private var primarySummary: String {
        let names = option.routeNames
        if names.isEmpty {
            return durationText
        }
        return "\(names.joined(separator: " · ")) · \(durationText)"
    }

    private var secondarySummary: String {
        let transfers = option.transferCount == 0 ? "Direct" : "\(option.transferCount) transfer\(option.transferCount == 1 ? "" : "s")"
        let liveSummary = option.usesLiveData ? "Live updates from mobiliteit.lu" : "Scheduled GTFS times"
        return "\(transfers) · \(distanceText) · \(liveSummary)"
    }

    private var durationText: String {
        let duration = option.plan.expectedTravelTime ?? 0
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes) min"
    }

    private var distanceText: String {
        let distance = option.plan.distanceMeters ?? 0
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return "\(Int(distance)) m"
    }

    private var cardBackground: AnyShapeStyle {
        AnyShapeStyle(
            Color(uiColor: .systemBackground).opacity(isSelected ? 0.92 : 0.76)
        )
    }

    private var cardStroke: Color {
        isSelected
            ? Color.blue.opacity(0.45)
            : Color(uiColor: .separator).opacity(0.22)
    }
}

private struct RouteOptionBadge: View {
    let status: RouteOptionStatus

    var body: some View {
        Text(status.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .viable: .green
        case .scheduledOnly: .secondary
        case .atRisk: .orange
        case .missed, .cancelled: .red
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .viable: .green.opacity(0.14)
        case .scheduledOnly: .secondary.opacity(0.12)
        case .atRisk: .orange.opacity(0.14)
        case .missed, .cancelled: .red.opacity(0.14)
        }
    }
}

private struct RouteInfoBanner: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct RouteStatusMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RouteLegList: View {
    let legs: [RoutePlan.Leg]
    @State private var markerCenters: [String: CGFloat] = [:]

    var body: some View {
        let displayLegs = legs.filter { $0.instruction != nil || $0.distanceMeters != nil }

        if !displayLegs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected route")
                    .font(.headline.weight(.semibold))

                ZStack(alignment: .topLeading) {
                    timelineRail(for: displayLegs)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayLegs) { leg in
                            RouteLegRow(leg: leg)
                        }
                    }
                }
                .coordinateSpace(.named(RouteLegTimelineLayout.coordinateSpace))
                .onPreferenceChange(TimelineMarkerCenterPreferenceKey.self) { centers in
                    markerCenters = centers
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func timelineRail(for displayLegs: [RoutePlan.Leg]) -> some View {
        let segments = railSegments(for: displayLegs)

        if !segments.isEmpty {
            Path { path in
                for segment in segments {
                    path.move(
                        to: CGPoint(
                            x: RouteLegTimelineLayout.markerCenterX,
                            y: segment.start
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: RouteLegTimelineLayout.markerCenterX,
                            y: segment.end
                        )
                    )
                }
            }
            .stroke(railColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private func railSegments(for displayLegs: [RoutePlan.Leg]) -> [(start: CGFloat, end: CGFloat)] {
        let centers = displayLegs.compactMap { markerCenters[$0.id] }
        guard centers.count > 1 else { return [] }

        return zip(centers.dropLast(), centers.dropFirst()).compactMap { current, next in
            let start = current + RouteLegTimelineLayout.markerRadius + RouteLegTimelineLayout.railGap
            let end = next - RouteLegTimelineLayout.markerRadius - RouteLegTimelineLayout.railGap
            guard end > start else { return nil }
            return (start, end)
        }
    }

    private var railColor: Color {
        Color(uiColor: .separator).opacity(0.45)
    }
}

private enum RouteLegTimelineLayout {
    static let markerColumnWidth: CGFloat = 28
    static let markerSize: CGFloat = 24
    static let markerRadius = markerSize / 2
    static let markerCenterX = markerColumnWidth / 2
    static let railGap: CGFloat = 7
    static let coordinateSpace = "RouteLegTimelineCoordinateSpace"
}

private struct TimelineMarkerCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, next in next }
    }
}

private struct RouteLegRow: View {
    let leg: RoutePlan.Leg

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timelineMarker
                .frame(width: RouteLegTimelineLayout.markerColumnWidth, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(leg.instruction ?? leg.transportKind.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)

                if let timeText {
                    Text(timeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let platform = leg.platform, !platform.isEmpty {
                    Text("Platform \(platform)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if leg.liveStatus != .scheduled {
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                if let transferWarning = leg.transferWarning {
                    Text(transferWarning)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }

                if let distanceMeters = leg.distanceMeters {
                    Text(distanceText(distanceMeters))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var timelineMarker: some View {
        ZStack {
            Circle()
                .fill(markerColor.opacity(0.16))

            Circle()
                .stroke(markerColor.opacity(0.85), lineWidth: 2)

            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(markerColor)
        }
        .frame(
            width: RouteLegTimelineLayout.markerSize,
            height: RouteLegTimelineLayout.markerSize
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TimelineMarkerCenterPreferenceKey.self,
                    value: [
                        leg.id: proxy.frame(
                            in: .named(RouteLegTimelineLayout.coordinateSpace)
                        ).midY
                    ]
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var markerColor: Color {
        if leg.transportKind == .walking {
            return .green
        }

        switch leg.mode {
        case .train:
            return .red
        case .tram:
            return .orange
        case .bus:
            return .blue
        case .funicular:
            return .purple
        case .walking:
            return .green
        case .unknown:
            return .secondary
        }
    }

    private var iconName: String {
        if leg.transportKind == .walking {
            return "figure.walk"
        }

        switch leg.mode {
        case .bus:
            return "bus.fill"
        case .tram:
            return "tram.fill"
        case .train:
            return "train.side.front.car"
        case .funicular:
            return "cablecar.fill"
        case .walking:
            return "figure.walk"
        case .unknown:
            return "tram.fill"
        }
    }

    private var timeText: String? {
        let departure = leg.realtimeDepartureTime
            ?? leg.scheduledDepartureTime
            ?? leg.departureTime
        let arrival = leg.realtimeArrivalTime
            ?? leg.scheduledArrivalTime
            ?? leg.arrivalTime
        guard let departure, let arrival else { return nil }
        return "\(departure.formatted(date: .omitted, time: .shortened))-\(arrival.formatted(date: .omitted, time: .shortened))"
    }

    private var statusText: String {
        if let delayMinutes = leg.delayMinutes, delayMinutes > 0 {
            return "\(leg.liveStatus.displayText) +\(delayMinutes) min"
        }
        return leg.liveStatus.displayText
    }

    private var statusColor: Color {
        switch leg.liveStatus {
        case .live:
            return .green
        case .delayed:
            return .orange
        case .cancelled:
            return .red
        case .unknown:
            return .secondary
        case .scheduled:
            return .secondary
        }
    }

    private func distanceText(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return "\(Int(distance)) m"
    }
}

#if DEBUG
#Preview("Route Options") {
    ScrollView {
        RouteView(
            viewModel: .previewWithRoutes,
            calculateRoute: {},
            selectRouteOption: { _ in },
            showMoreRouteOptions: {},
            openInAppleMaps: {}
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Waiting For Location") {
    RouteView(
        viewModel: .previewWaitingForLocation,
        calculateRoute: {},
        selectRouteOption: { _ in },
        showMoreRouteOptions: {},
        openInAppleMaps: {}
    )
    .padding()
}

#Preview("Route Timeline") {
    ScrollView {
        RouteTimelineView(
            viewModel: .previewWithRoutes,
            openInAppleMaps: {}
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

private extension RoutePresentationModel {
    static var previewWithRoutes: RoutePresentationModel {
        RoutePresentationModel(
            selectedStop: .previewDestination,
            routeOptions: [.previewTramOption, .previewBusOption],
            selectedRouteOptionID: "tram-route",
            visibleRouteOptionCount: 2,
            loadingPhase: .idle,
            errorMessage: nil,
            statusMessage: "Fastest public transport option from your current location."
        )
    }

    static var previewWaitingForLocation: RoutePresentationModel {
        RoutePresentationModel(
            selectedStop: .previewDestination,
            routeOptions: [],
            selectedRouteOptionID: nil,
            visibleRouteOptionCount: 0,
            loadingPhase: .waitingForLocation,
            errorMessage: nil,
            statusMessage: nil
        )
    }
}

private extension RouteOption {
    static var previewTramOption: RouteOption {
        RouteOption(
            id: "tram-route",
            plan: RoutePlan(
                id: "tram-plan",
                origin: .previewOrigin,
                destination: .previewDestinationPoint,
                expectedTravelTime: 18 * 60,
                distanceMeters: 4300,
                legs: [
                    RoutePlan.Leg(
                        id: "walk-to-tram",
                        mode: .walking,
                        instruction: "Walk to Hamilius",
                        transportKind: .walking,
                        origin: .previewOrigin,
                        destination: .previewTransfer,
                        departureTime: Date(),
                        arrivalTime: Date().addingTimeInterval(4 * 60),
                        distanceMeters: 350
                    ),
                    RoutePlan.Leg(
                        id: "tram-leg",
                        mode: .tram,
                        instruction: "Take tram T1 toward Luxexpo",
                        transportKind: .transit,
                        routeName: "T1",
                        origin: .previewTransfer,
                        destination: .previewDestinationPoint,
                        departureTime: Date().addingTimeInterval(6 * 60),
                        arrivalTime: Date().addingTimeInterval(18 * 60),
                        realtimeDepartureTime: Date().addingTimeInterval(7 * 60),
                        realtimeArrivalTime: Date().addingTimeInterval(19 * 60),
                        distanceMeters: 3950,
                        platform: "2",
                        delayMinutes: 1,
                        liveStatus: .live
                    )
                ],
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }

    static var previewBusOption: RouteOption {
        RouteOption(
            id: "bus-route",
            plan: RoutePlan(
                id: "bus-plan",
                origin: .previewOrigin,
                destination: .previewDestinationPoint,
                expectedTravelTime: 24 * 60,
                distanceMeters: 4800,
                legs: [
                    RoutePlan.Leg(
                        id: "bus-leg",
                        mode: .bus,
                        instruction: "Take bus 16 toward Kirchberg",
                        transportKind: .transit,
                        routeName: "16",
                        origin: .previewOrigin,
                        destination: .previewDestinationPoint,
                        departureTime: Date().addingTimeInterval(9 * 60),
                        arrivalTime: Date().addingTimeInterval(24 * 60),
                        distanceMeters: 4800
                    )
                ],
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }
}

private extension Stop {
    static var previewDestination: Stop {
        Stop(
            id: "stop-luxexpo",
            name: "Luxexpo",
            locality: "Kirchberg",
            location: .previewDestinationPoint,
            modes: [.tram, .bus],
            dataSource: .mock
        )
    }
}

private extension LocationPoint {
    static var previewOrigin: LocationPoint {
        LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319)
    }

    static var previewTransfer: LocationPoint {
        LocationPoint(id: "hamilius", name: "Hamilius", latitude: 49.6111, longitude: 6.1275)
    }

    static var previewDestinationPoint: LocationPoint {
        LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746)
    }
}
#endif
