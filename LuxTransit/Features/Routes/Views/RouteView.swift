import SwiftUI

// MARK: - RouteView

/// The route-planner sheet context (``TransitSheetContext/directions``).
///
/// Composes a unified endpoints card, compact filter bar, state-driven middle
/// section (loading skeletons, error/empty cards, results list), and a primary
/// Find Routes action. All business logic lives upstream — this view is fully
/// stateless, driven by ``RoutePresentationModel`` and closure callbacks.
struct RouteView: View {
    let viewModel: RoutePresentationModel
    let calculateRoute: () -> Void
    let selectRouteOption: (String) -> Void
    let showMoreRouteOptions: () -> Void
    let openInAppleMaps: () -> Void
    let selectRouteOrigin: (RoutePlace?) -> Void
    let selectRouteDestination: (RoutePlace) -> Void
    let applyCommutePreset: (String) -> Void
    let saveCurrentCommutePreset: (String) -> Void
    let swapRouteEndpoints: () -> Void
    let updateRouteFilters: (RoutePlannerFilters) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── From / To unified card ────────────────────────────────────
            RouteEndpointsCard(
                viewModel: viewModel,
                selectRouteOrigin: selectRouteOrigin,
                selectRouteDestination: selectRouteDestination,
                swapRouteEndpoints: swapRouteEndpoints
            )

            // ── Commute presets ───────────────────────────────────────────
            if !viewModel.commutePresets.isEmpty {
                commutePresetsRow
            }

            // ── Recent trips ──────────────────────────────────────────────
            if !viewModel.recentTrips.isEmpty {
                recentTripsRow
            }

            // ── Sort + options bar ────────────────────────────────────────
            RouteOptionsBar(
                filters: viewModel.filters,
                hasDestination: viewModel.hasDestination,
                updateRouteFilters: updateRouteFilters,
                saveCurrentCommutePreset: saveCurrentCommutePreset
            )

            // ── Primary action ────────────────────────────────────────────
            findRoutesButton

            // ── State-driven body ─────────────────────────────────────────
            stateBody

            // ── Share + Apple Maps handoff ────────────────────────────────
            if let option = viewModel.selectedRouteOption {
                ShareLink(
                    item: option.shareText(
                        originTitle: viewModel.originTitle,
                        destinationTitle: viewModel.destinationTitle
                    )
                ) {
                    Label("Share route", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)
            }

            if viewModel.hasDestination {
                Button(action: openInAppleMaps) {
                    Label("Open in Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Commute presets

    private var commutePresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.commutePresets) { preset in
                    Button {
                        applyCommutePreset(preset.id)
                    } label: {
                        Label(preset.title, systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 1) // avoid clipping focus rings
        }
    }

    // MARK: - Recent trips

    private var recentTripsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.recentTrips) { trip in
                    Button {
                        applyCommutePreset(trip.id)
                    } label: {
                        Label(trip.title, systemImage: "clock.arrow.circlepath")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Find Routes button

    private var findRoutesButton: some View {
        Button(action: calculateRoute) {
            HStack {
                if viewModel.isCalculating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(calculateButtonTitle)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(
            !viewModel.hasDestination
                || viewModel.isCalculating
                || viewModel.isWaitingForLocation
        )
    }

    private var calculateButtonTitle: String {
        if viewModel.isWaitingForLocation { return "Waiting for Location" }
        if viewModel.isCalculating { return "Finding Routes…" }
        return viewModel.routeOptions.isEmpty ? "Find Routes" : "Refresh Routes"
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var stateBody: some View {
        // Waiting for GPS
        if viewModel.isWaitingForLocation {
            DepartureLoadingCard(title: "Waiting for current location")
        }

        // Initial load: show skeleton cards instead of a lone spinner
        if viewModel.isCalculating, viewModel.routeOptions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Route options")
                    .font(.headline.weight(.semibold))
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
            }
        }

        // Inline refresh banner when results are already visible
        if viewModel.isCalculating, !viewModel.routeOptions.isEmpty {
            RouteInfoBanner(
                title: "Refreshing routes",
                systemImage: "arrow.trianglehead.clockwise"
            )
        }

        // Error
        if let errorMessage = viewModel.errorMessage {
            CompactUnavailableCard(
                title: "Route unavailable",
                message: errorMessage,
                systemImage: "tram.fill"
            )
        }

        // Empty — no route selected yet; offer quick destination picks
        if !viewModel.isCalculating,
           !viewModel.isWaitingForLocation,
           viewModel.routeOptions.isEmpty,
           viewModel.errorMessage == nil {
            emptyState
        }

        // Status note
        if let statusMessage = viewModel.statusMessage {
            RouteStatusMessage(text: statusMessage)
        }

        // Journey alerts
        if !viewModel.alerts.isEmpty {
            RouteAlertsSection(alerts: viewModel.alerts)
        }

        // Cross-border hint
        if viewModel.selectedRouteOption?.crossesBorder == true {
            RouteInfoBanner(
                title: "Crosses a border — CFL / SNCF / DB live data may be incomplete",
                systemImage: "flag.checkered"
            )
        }

        // Results
        if !viewModel.routeOptions.isEmpty {
            routeResultsSection
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompactUnavailableCard(
                title: "No destination selected",
                message: "Choose a destination above to see public transport options.",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )

            // Quick-pick chips from favourites + nearby
            let quickPicks = (viewModel.favouritePlaces + viewModel.nearbyPlaces).prefix(6)
            if !quickPicks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick destinations")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlexibleWrappingRow(spacing: 8) {
                        ForEach(Array(quickPicks)) { place in
                            Button {
                                selectRouteDestination(place)
                            } label: {
                                Label(
                                    place.title,
                                    systemImage: place.source == .favourite ? "bookmark.fill" : "location.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results section

    private var routeResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route options")
                .font(.headline.weight(.semibold))

            ForEach(viewModel.visibleRouteOptions) { option in
                RouteOptionCard(
                    option: option,
                    isSelected: option.id == viewModel.selectedRouteOptionID,
                    selectRouteOption: { selectRouteOption(option.id) }
                )
            }

            if viewModel.canShowMoreRouteOptions {
                Button(action: showMoreRouteOptions) {
                    Label("Show more routes", systemImage: "plus.circle")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - RouteTimelineView

/// The route step-by-step timeline sheet context (``TransitSheetContext/routeTimeline``).
///
/// Shows a summary card for the selected option (ribbon + times) followed by
/// the vertical-rail leg list. Falls back to an unavailable card if no option
/// is selected.
struct RouteTimelineView: View {
    let viewModel: RoutePresentationModel
    let openInAppleMaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedOption = viewModel.selectedRouteOption {
                // Summary card matching the chosen option card
                RouteTimelineSummaryCard(option: selectedOption)

                // Vertical leg-by-leg timeline
                RouteLegList(legs: selectedOption.plan.legs, legAlerts: viewModel.legAlerts)

                // Journey alerts
                if !viewModel.alerts.isEmpty {
                    RouteAlertsSection(alerts: viewModel.alerts)
                }
            } else {
                CompactUnavailableCard(
                    title: "No route selected",
                    message: "Choose a route option to see its step-by-step timeline.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }

            // Apple Maps handoff
            Button(action: openInAppleMaps) {
                Label("Open in Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.primary)
            .disabled(viewModel.selectedStop == nil && viewModel.destination == nil)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - FlexibleWrappingRow

/// A simple flow layout that wraps its children into multiple rows.
private struct FlexibleWrappingRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                totalHeight = currentY
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: containerWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Route Options") {
        ScrollView {
            RouteView(
                viewModel: .previewWithRoutes,
                calculateRoute: {},
                selectRouteOption: { _ in },
                showMoreRouteOptions: {},
                openInAppleMaps: {},
                selectRouteOrigin: { _ in },
                selectRouteDestination: { _ in },
                applyCommutePreset: { _ in },
                saveCurrentCommutePreset: { _ in },
                swapRouteEndpoints: {},
                updateRouteFilters: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Calculating (skeleton)") {
        ScrollView {
            RouteView(
                viewModel: .previewCalculating,
                calculateRoute: {},
                selectRouteOption: { _ in },
                showMoreRouteOptions: {},
                openInAppleMaps: {},
                selectRouteOrigin: { _ in },
                selectRouteDestination: { _ in },
                applyCommutePreset: { _ in },
                saveCurrentCommutePreset: { _ in },
                swapRouteEndpoints: {},
                updateRouteFilters: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Waiting For Location") {
        ScrollView {
            RouteView(
                viewModel: .previewWaitingForLocation,
                calculateRoute: {},
                selectRouteOption: { _ in },
                showMoreRouteOptions: {},
                openInAppleMaps: {},
                selectRouteOrigin: { _ in },
                selectRouteDestination: { _ in },
                applyCommutePreset: { _ in },
                saveCurrentCommutePreset: { _ in },
                swapRouteEndpoints: {},
                updateRouteFilters: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Empty state") {
        ScrollView {
            RouteView(
                viewModel: .previewEmpty,
                calculateRoute: {},
                selectRouteOption: { _ in },
                showMoreRouteOptions: {},
                openInAppleMaps: {},
                selectRouteOrigin: { _ in },
                selectRouteDestination: { _ in },
                applyCommutePreset: { _ in },
                saveCurrentCommutePreset: { _ in },
                swapRouteEndpoints: {},
                updateRouteFilters: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Error state") {
        ScrollView {
            RouteView(
                viewModel: .previewError,
                calculateRoute: {},
                selectRouteOption: { _ in },
                showMoreRouteOptions: {},
                openInAppleMaps: {},
                selectRouteOrigin: { _ in },
                selectRouteDestination: { _ in },
                applyCommutePreset: { _ in },
                saveCurrentCommutePreset: { _ in },
                swapRouteEndpoints: {},
                updateRouteFilters: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
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

    // MARK: Preview data

    private extension RoutePresentationModel {
        static var previewWithRoutes: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [RoutePlace(stop: .previewDestinationStop, source: .favourite)],
                nearbyPlaces: [RoutePlace(stop: .previewDestinationStop, source: .nearby)],
                recentPlaces: [],
                commutePresets: [
                    RouteCommutePreset(
                        title: "Kirchberg",
                        origin: nil,
                        destination: RoutePlace(stop: .previewDestinationStop, source: .preset)
                    )
                ],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [.previewTramRoute, .previewBusRoute],
                alerts: [
                    AlertMessage(
                        id: "alert-1",
                        title: "T1 line disruption",
                        body: "Expect longer boarding times between Hamilius and Philharmonie.",
                        severity: .warning,
                        affectedStopIds: [],
                        affectedRouteIds: ["T1"],
                        startsAt: .now,
                        endsAt: nil,
                        dataSource: .mock
                    )
                ],
                selectedRouteOptionID: "tram-route",
                visibleRouteOptionCount: 2,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: "Fastest option from your current location."
            )
        }

        static var previewCalculating: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .calculating,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewWaitingForLocation: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .waitingForLocation,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewEmpty: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: nil,
                origin: nil,
                destination: nil,
                favouritePlaces: [RoutePlace(stop: .previewDestinationStop, source: .favourite)],
                nearbyPlaces: [
                    RoutePlace(stop: .previewDestinationStop, source: .nearby),
                    RoutePlace(
                        title: "Clausen",
                        subtitle: "Clausen",
                        location: LocationPoint(id: "clausen", name: "Clausen", latitude: 49.6116, longitude: 6.132),
                        source: .nearby
                    )
                ],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewError: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .idle,
                errorMessage: "No public transport routes found between these locations. Try adjusting your destination.",
                statusMessage: nil
            )
        }
    }

    private extension Stop {
        static var previewDestinationStop: Stop {
            Stop(
                id: "stop-luxexpo",
                name: "Luxexpo",
                locality: "Kirchberg",
                location: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                modes: [.tram, .bus],
                dataSource: .mock
            )
        }
    }

    private extension RouteOption {
        static var previewTramRoute: RouteOption {
            RouteOption(
                id: "tram-route",
                plan: RoutePlan(
                    id: "tram-plan",
                    origin: LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319),
                    destination: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                    expectedTravelTime: 18 * 60,
                    distanceMeters: 4300,
                    legs: [
                        RoutePlan.Leg(
                            id: "walk-to-tram",
                            mode: .walking,
                            instruction: "Walk to Hamilius",
                            transportKind: .walking,
                            origin: LocationPoint(
                                id: "origin",
                                name: "Current Location",
                                latitude: 49.6116,
                                longitude: 6.1319
                            ),
                            destination: LocationPoint(
                                id: "hamilius",
                                name: "Hamilius",
                                latitude: 49.6111,
                                longitude: 6.1275
                            ),
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
                            origin: LocationPoint(
                                id: "hamilius",
                                name: "Hamilius",
                                latitude: 49.6111,
                                longitude: 6.1275
                            ),
                            destination: LocationPoint(
                                id: "luxexpo",
                                name: "Luxexpo",
                                latitude: 49.6329,
                                longitude: 6.1746
                            ),
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

        static var previewBusRoute: RouteOption {
            RouteOption(
                id: "bus-route",
                plan: RoutePlan(
                    id: "bus-plan",
                    origin: LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319),
                    destination: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                    expectedTravelTime: 24 * 60,
                    distanceMeters: 4800,
                    legs: [
                        RoutePlan.Leg(
                            id: "bus-leg",
                            mode: .bus,
                            instruction: "Take bus 16 toward Kirchberg",
                            transportKind: .transit,
                            routeName: "16",
                            origin: LocationPoint(
                                id: "origin",
                                name: "Current Location",
                                latitude: 49.6116,
                                longitude: 6.1319
                            ),
                            destination: LocationPoint(
                                id: "luxexpo",
                                name: "Luxexpo",
                                latitude: 49.6329,
                                longitude: 6.1746
                            ),
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
#endif
