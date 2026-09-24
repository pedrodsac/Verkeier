import SwiftUI

// MARK: - RouteView

/// The route-planner navigation destination.
///
/// Composes a unified endpoints card, state-driven middle section (loading
/// skeletons, error/empty cards, results list), and a primary Find Routes
/// action. All business logic lives upstream — this view is fully stateless,
/// driven by ``RoutePresentationModel`` and closure callbacks.
struct RouteView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── From / To unified card ────────────────────────────────────
            RouteEndpointsCard(
                viewModel: viewModel,
                showRoutePlaceSearch: actions.showRoutePlaceSearch,
                swapRouteEndpoints: actions.swapRouteEndpoints
            )

            // ── Commute presets ───────────────────────────────────────────
            if !viewModel.commutePresets.isEmpty {
                commutePresetsRow
            }

            // ── Recent trips ──────────────────────────────────────────────
            if !viewModel.recentTrips.isEmpty {
                recentTripsRow
            }

            // ── Primary action ────────────────────────────────────────────
            findRoutesButton

            // ── State-driven body ─────────────────────────────────────────
            stateBody

            // ── Apple Maps handoff ────────────────────────────────────────
            if viewModel.hasDestination {
                Button(action: actions.openInAppleMaps) {
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
        // Haptic when a route plan is found.
        .sensoryFeedback(.success, trigger: viewModel.routeOptions.count)
    }

    // MARK: - Commute presets

    private var commutePresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.commutePresets) { preset in
                    Button {
                        actions.applyAndCalculatePreset(preset.id)
                    } label: {
                        Label(preset.title, systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }
            .safeAreaPadding(.horizontal, 1) // avoid clipping focus rings
        }
    }

    // MARK: - Recent trips

    private var recentTripsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.recentTrips) { trip in
                    Button {
                        actions.applyAndCalculatePreset(trip.id)
                    } label: {
                        Label(trip.title, systemImage: "clock.arrow.circlepath")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)
                }
            }
            .safeAreaPadding(.horizontal, 1)
        }
    }

    // MARK: - Find Routes button

    private var findRoutesButton: some View {
        Button(action: actions.calculateRoute) {
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
        if viewModel.isWaitingForLocation { return "Waiting for Location..." }
        if viewModel.isCalculating { return "Finding Routes…" }
        return viewModel.routeOptions.isEmpty ? "Find Routes" : "Refresh Routes"
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var stateBody: some View {

        // Initial load: show skeleton cards instead of a lone spinner
        if viewModel.isCalculating, viewModel.routeOptions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
            }
        }

        // Error
        if let errorMessage = viewModel.errorMessage, viewModel.routeOptions.isEmpty {
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

        if viewModel.isStale {
            RouteStatusMessage(text: "Routes may have changed. Refresh routes for the latest information.")
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
        if !viewModel.routeOptions.isEmpty || !viewModel.supplementalRouteOptions.isEmpty {
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
                                actions.selectRouteDestination(place)
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
            ForEach(viewModel.chronologicallyOrderedRouteOptions) { option in
                RouteOptionCard(
                    option: option,
                    isSelected: option.id == viewModel.selectedRouteOptionID,
                )
            }

            if viewModel.routeOptions.contains(where: { !$0.transitLegs.isEmpty }) {
                HStack(spacing: 10) {
                    routePageButton(
                        title: "Earlier",
                        systemImage: "chevron.left",
                        isLoading: viewModel.isLoadingEarlierRoutes,
                        isEnabled: viewModel.canLoadEarlierRoutes,
                        action: actions.loadEarlierRoutes
                    )
                    routePageButton(
                        title: "Later",
                        systemImage: "chevron.right",
                        isLoading: viewModel.isLoadingLaterRoutes,
                        isEnabled: viewModel.canLoadLaterRoutes,
                        action: actions.loadLaterRoutes
                    )
                }
            }

            if !viewModel.supplementalRouteOptions.isEmpty {
                Text("Bike option")
                    .font(.headline)
                    .padding(.top, 6)
                ForEach(viewModel.supplementalRouteOptions) { option in
                    RouteOptionCard(
                        option: option,
                        isSelected: option.id == viewModel.selectedRouteOptionID
                    )
                }
            }
        }
    }

    private func routePageButton(
        title: String,
        systemImage: String,
        isLoading: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled || viewModel.isLoadingEarlierRoutes || viewModel.isLoadingLaterRoutes)
    }
}
