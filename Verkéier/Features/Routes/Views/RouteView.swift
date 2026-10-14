import MobiliteitKit
import SwiftUI

/// The route planner: endpoints, saved commutes, and the route options found
/// for them. ``PlanView`` hosts it on the Plan tab and for a commute preset.
struct RouteView: View {
    @Environment(RoutePlannerModel.self) private var model
    @Environment(AlertsModel.self) private var alerts
    @Environment(FavouritesModel.self) private var favourites
    @Environment(MapModel.self) private var map
    @Environment(SheetRouter.self) private var router
    @Environment(LocationService.self) private var locationService
    @Environment(\.routeService) private var routeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── From / To unified card ────────────────────────────────────
            RouteEndpointsCard(
                origin: model.routeOrigin,
                destination: model.routeDestination,
                hasCurrentLocation: locationService.currentLocation != nil,
                showRoutePlaceSearch: router.showRoutePlaceSearch,
                swapRouteEndpoints: router.swapRouteEndpoints
            )

            // ── Commute presets ───────────────────────────────────────────
            if !model.commutePresets.isEmpty {
                commutePresetsRow
            }

            // ── Recent trips ──────────────────────────────────────────────
            if !model.recentTrips.isEmpty {
                recentTripsRow
            }

            // ── State-driven body ─────────────────────────────────────────
            stateBody

            // ── Apple Maps handoff ────────────────────────────────────────
            if model.hasDestination {
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
        .task(id: [
            model.routeOrigin?.id, model.routeDestination?.id,
            locationService.currentLocation == nil ? nil : "location-available",
        ]) {
            await router.maintainRoutes()
        }
        // Haptic when a route plan is found.
        .sensoryFeedback(.success, trigger: model.routeOptions.count)
        .onChange(of: model.routeStatusMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .background {
            if !model.isCalculatingRoute, !model.isLoadingEarlierRoutes, !model.isLoadingLaterRoutes,
                !model.routeOptions.isEmpty,
                let requestID = model.routeDiagnostics?.requestID
            {
                RouteRenderObserver(requestID: requestID, rendered: model.recordRouteResultsRendered)
                    .frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
    }

    // MARK: - Commute presets

    private var commutePresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.commutePresets) { preset in
                    Button {
                        router.applyAndCalculatePreset(preset.id)
                    } label: {
                        Label(preset.title, systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }
            .safeAreaPadding(.horizontal, 1)  // avoid clipping focus rings
        }
    }

    // MARK: - Recent trips

    private var recentTripsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recentTrips) { trip in
                    Button {
                        router.applyAndCalculatePreset(trip.id)
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

    // MARK: - State-driven body

    @ViewBuilder
    private var stateBody: some View {

        if model.isWaitingForRouteLocation {
            ProgressView("Waiting for Location…")
                .frame(maxWidth: .infinity)
        }

        // Initial load: show skeleton cards instead of a lone spinner
        if model.isCalculatingRoute, model.routeOptions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
                RouteOptionSkeletonRow()
            }
        }

        // Error
        if let errorMessage = model.routeErrorMessage, model.routeOptions.isEmpty {
            CompactUnavailableCard(
                title: "Route unavailable",
                message: errorMessage,
                systemImage: "tram.fill"
            )
        }

        // Empty — no route selected yet; offer quick destination picks
        if !model.isCalculatingRoute,
            !model.isWaitingForRouteLocation,
            model.routeOptions.isEmpty,
            model.routeErrorMessage == nil
        {
            emptyState
        }

        // Status note
        if let statusMessage = model.routeStatusMessage {
            RouteStatusMessage(text: statusMessage)
        }

        // Journey alerts
        let routeAlerts = alerts.alerts(forRoute: model.selectedRouteOption)
        if !routeAlerts.isEmpty {
            RouteAlertsSection(alerts: routeAlerts)
        }

        // Cross-border hint
        if model.selectedRouteOption?.crossesBorder == true {
            RouteInfoBanner(
                title: "Crosses a border — CFL / SNCF / DB live data may be incomplete",
                systemImage: "flag.checkered"
            )
        }

        // Results
        if !model.routeOptions.isEmpty || !model.supplementalRouteOptions.isEmpty {
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
            let quickPicks = quickDestinations
            if !quickPicks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick destinations")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlexibleWrappingRow(spacing: 8) {
                        ForEach(Array(quickPicks)) { place in
                            Button {
                                router.selectRouteDestination(place)
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.chronologicallyOrderedRouteOptions) { option in
                    RouteOptionCard(
                        option: option,
                        isSelected: option.id == model.selectedRouteOptionID,
                    )
                    .transition(routeCardTransition)
                }
            }

            if model.routeOptions.contains(where: { !$0.transitLegs.isEmpty }) {
                HStack(spacing: 10) {
                    routePageButton(
                        title: "Earlier",
                        systemImage: "chevron.left",
                        isLoading: model.isLoadingEarlierRoutes,
                        isEnabled: model.canLoadEarlierRoutes,
                        icon: .leading,
                        action: loadEarlierRoutes
                    )
                    routePageButton(
                        title: "Later",
                        systemImage: "chevron.right",
                        isLoading: model.isLoadingLaterRoutes,
                        isEnabled: model.canLoadLaterRoutes,
                        icon: .trailing,
                        action: loadLaterRoutes
                    )
                }
            }

            if !model.supplementalRouteOptions.isEmpty {
                ForEach(model.supplementalRouteOptions) { option in
                    RouteOptionCard(
                        option: option,
                        isSelected: option.id == model.selectedRouteOptionID
                    )
                    .transition(routeCardTransition)
                }
            }
        }
        // Earlier/Later insert cards around the listed ones; a refresh
        // crossfades to the replacement set.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .snappy,
            value: model.routeOptions.map(\.id) + model.supplementalRouteOptions.map(\.id)
        )
    }

    private var routeCardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95))
    }

    private func routePageButton(
        title: String,
        systemImage: String,
        isLoading: Bool,
        isEnabled: Bool,
        icon: HorizontalAlignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                switch icon {
                case .leading:
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                case .trailing:
                    Text(title)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                    }
                default: EmptyView()
                }

            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled || model.isLoadingEarlierRoutes || model.isLoadingLaterRoutes)
    }

    // MARK: - Actions

    /// Favourites first, then nearby stops, as one-tap destinations.
    private var quickDestinations: ArraySlice<RoutePlace> {
        let favouritePlaces = favourites.favouriteStops.map { RoutePlace(stop: $0, source: .favourite) }
        let nearbyPlaces = map.distinctNearbyStops.map { RoutePlace(stop: $0, source: .nearby) }
        return (favouritePlaces + nearbyPlaces).prefix(6)
    }

    private func openInAppleMaps() {
        model.openSelectedRouteInAppleMaps(using: routeService, from: locationService.currentLocation)
    }

    private func loadEarlierRoutes() {
        Task { await model.loadEarlierRoutes(using: routeService, from: locationService.currentLocation) }
    }

    private func loadLaterRoutes() {
        Task { await model.loadLaterRoutes(using: routeService, from: locationService.currentLocation) }
    }
}
