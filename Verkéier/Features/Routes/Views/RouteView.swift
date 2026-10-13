import SwiftUI

// MARK: - RouteView

/// The route-planner navigation destination.
///
/// Composes a unified endpoints card, state-driven middle section (loading
/// skeletons, error/empty cards, results list). All business logic lives upstream — this view is fully stateless,
/// driven by ``RoutePresentationModel`` and closure callbacks.
struct RouteView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .task(id: [viewModel.origin?.id, viewModel.selectedPlace(for: .destination)?.id,
                   viewModel.currentLocation == nil ? nil : "location-available"]) {
            await actions.maintainRoutes()
        }
        // Haptic when a route plan is found.
        .sensoryFeedback(.success, trigger: viewModel.routeOptions.count)
        .onChange(of: viewModel.statusMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .background {
            if !viewModel.isCalculating, !viewModel.isLoadingEarlierRoutes, !viewModel.isLoadingLaterRoutes,
               !viewModel.routeOptions.isEmpty,
               let requestID = viewModel.diagnosticRequestID {
                RouteRenderObserver(requestID: requestID, rendered: viewModel.resultsRendered)
                    .frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
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

    // MARK: - State-driven body

    @ViewBuilder
    private var stateBody: some View {

        if viewModel.isWaitingForLocation {
            ProgressView("Waiting for Location…")
                .frame(maxWidth: .infinity)
        }

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
        VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 10) {
				ForEach(viewModel.chronologicallyOrderedRouteOptions) { option in
					RouteOptionCard(
						option: option,
						isSelected: option.id == viewModel.selectedRouteOptionID,
					)
					.transition(routeCardTransition)
				}
			}

            if viewModel.routeOptions.contains(where: { !$0.transitLegs.isEmpty }) {
                HStack(spacing: 10) {
                    routePageButton(
                        title: "Earlier",
                        systemImage: "chevron.left",
                        isLoading: viewModel.isLoadingEarlierRoutes,
                        isEnabled: viewModel.canLoadEarlierRoutes,
						icon: .leading,
                        action: actions.loadEarlierRoutes
                    )
                    routePageButton(
                        title: "Later",
                        systemImage: "chevron.right",
                        isLoading: viewModel.isLoadingLaterRoutes,
                        isEnabled: viewModel.canLoadLaterRoutes,
						icon: .trailing,
                        action: actions.loadLaterRoutes
                    )
                }
            }

            if !viewModel.supplementalRouteOptions.isEmpty {
                ForEach(viewModel.supplementalRouteOptions) { option in
                    RouteOptionCard(
                        option: option,
                        isSelected: option.id == viewModel.selectedRouteOptionID
                    )
                    .transition(routeCardTransition)
                }
            }
        }
        // Earlier/Later insert cards around the listed ones; a refresh
        // crossfades to the replacement set.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .snappy,
            value: viewModel.routeOptions.map(\.id) + viewModel.supplementalRouteOptions.map(\.id)
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
        .disabled(!isEnabled || viewModel.isLoadingEarlierRoutes || viewModel.isLoadingLaterRoutes)
    }
}
