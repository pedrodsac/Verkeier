import SwiftUI

// MARK: - RouteView

/// The route-planner navigation destination.
///
/// Composes a unified endpoints card, compact filter bar, state-driven middle
/// section (loading skeletons, error/empty cards, results list), and a primary
/// Find Routes action. All business logic lives upstream — this view is fully
/// stateless, driven by ``RoutePresentationModel`` and closure callbacks.
struct RouteView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── From / To unified card ────────────────────────────────────
            RouteEndpointsCard(
                viewModel: viewModel,
                selectRouteOrigin: actions.selectRouteOrigin,
                selectRouteDestination: actions.selectRouteDestination,
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

            // ── Sort + options bar ────────────────────────────────────────
            RouteOptionsBar(
                filters: viewModel.filters,
                hasDestination: viewModel.hasDestination,
                updateRouteFilters: actions.updateRouteFilters,
                saveCurrentCommutePreset: actions.saveCurrentCommutePreset
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
                        actions.applyCommutePreset(preset.id)
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
                        actions.applyCommutePreset(trip.id)
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
            Text("Route options")
                .font(.headline.weight(.semibold))

            ForEach(viewModel.visibleRouteOptions) { option in
                RouteOptionCard(
                    option: option,
                    isSelected: option.id == viewModel.selectedRouteOptionID,
                )
            }

            if viewModel.canShowMoreRouteOptions {
                Button(action: actions.showMoreRouteOptions) {
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
