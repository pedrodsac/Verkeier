import SwiftUI

/// One native list owns planning inputs, suggestions, and journey results.
/// All route calculations and state changes remain in the injected actions.
struct RouteView: View {
    let viewModel: RoutePresentationModel
    let actions: RouteActions

    @State private var selectedRecentTripID: String?

    var body: some View {
        List {
            RouteEndpointsSection(
                viewModel: viewModel,
                showRoutePlaceSearch: actions.showRoutePlaceSearch,
                swapRouteEndpoints: actions.swapRouteEndpoints
            )
            .environment(\.editMode, .constant(.active))

            Group {
                savedTripsSections
                stateSections

                if viewModel.hasDestination {
                    Section {
                        Button(action: actions.openInAppleMaps) {
                            Label("Open in Apple Maps", systemImage: "map")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        // List-wide editing suppresses navigation selection. Only the endpoint
        // section opts into editing; pickers and route links stay interactive.
        .environment(\.editMode, .constant(.inactive))
        .onChange(of: viewModel.selectedRecentTripID, initial: true) { _, tripID in
            selectedRecentTripID = tripID
        }
        .onChange(of: selectedRecentTripID) { _, tripID in
            guard let tripID, tripID != viewModel.selectedRecentTripID else { return }
            actions.applyAndCalculatePreset(tripID)
        }
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

    @ViewBuilder
    private var savedTripsSections: some View {
        if !viewModel.commutePresets.isEmpty {
            Section("Saved trips") {
                ForEach(viewModel.commutePresets) { preset in
                    Button {
                        actions.applyAndCalculatePreset(preset.id)
                    } label: {
                        Label(preset.title, systemImage: "bookmark.fill")
                    }
                }
            }
        }

        if !viewModel.recentTrips.isEmpty {
            Section {
                Picker(selection: $selectedRecentTripID) {
                    Text("Choose a trip").tag(String?.none)
                    ForEach(viewModel.recentTrips) { trip in
                        Text(trip.title).tag(Optional(trip.id))
                    }
                } label: {
                    Label("Recent trips", systemImage: "clock.arrow.circlepath")
                }
                .pickerStyle(.navigationLink)
            }
        }
    }

    @ViewBuilder
    private var stateSections: some View {
        if viewModel.isWaitingForLocation {
            Section {
                ProgressView("Waiting for Location…")
                    .frame(maxWidth: .infinity)
            }
        }

        if viewModel.isCalculating, viewModel.routeOptions.isEmpty {
            Section("Finding routes") {
                ForEach(0..<3) { _ in
                    RouteOptionSkeletonRow()
                }
            }
        }

        if let errorMessage = viewModel.errorMessage, viewModel.routeOptions.isEmpty {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route unavailable").font(.headline)
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "tram.fill").foregroundStyle(.secondary)
                }
            }
        }

        if !viewModel.isCalculating,
           !viewModel.isWaitingForLocation,
           viewModel.routeOptions.isEmpty,
           viewModel.errorMessage == nil {
            emptySections
        }

        if viewModel.statusMessage != nil || viewModel.isStale {
            Section {
                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if viewModel.isStale {
                    Label("Routes may have changed. Pull to refresh for the latest information.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if !viewModel.alerts.isEmpty {
            Section("Journey Alerts") {
                ForEach(viewModel.alerts.prefix(3)) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(alert.title, systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        Text(alert.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if viewModel.selectedRouteOption?.crossesBorder == true {
            Section {
                Label("Crosses a border — CFL / SNCF / DB live data may be incomplete",
                      systemImage: "flag.checkered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if !viewModel.routeOptions.isEmpty || !viewModel.supplementalRouteOptions.isEmpty {
            resultsSections
        }
    }

    @ViewBuilder
    private var emptySections: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.hasDestination ? "No routes found" : "No destination selected")
                        .font(.headline)
                    Text(viewModel.hasDestination
                         ? "Try a different time or adjust your route options."
                         : "Choose a destination above to see public transport options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(.secondary)
            }
        }

        let quickPicks = (viewModel.favouritePlaces + viewModel.nearbyPlaces).prefix(6)
        if !quickPicks.isEmpty {
            Section("Quick destinations") {
                ForEach(quickPicks.enumerated(), id: \.offset) { _, place in
                    Button {
                        actions.selectRouteDestination(place)
                    } label: {
                        Label(place.displayTitle, systemImage: place.source == .favourite ? "bookmark.fill" : "mappin")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        Section("Routes") {
            ForEach(viewModel.chronologicallyOrderedRouteOptions) { option in
                RouteOptionRow(option: option, isSelected: option.id == viewModel.selectedRouteOptionID)
                    .listRowBackground(option.hasTightTransfer ? Color.orange.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
            }
        }

        if viewModel.routeOptions.contains(where: { !$0.transitLegs.isEmpty }) {
            Section {
                routePageButton(title: "Earlier", systemImage: "chevron.up",
                                isLoading: viewModel.isLoadingEarlierRoutes,
                                isEnabled: viewModel.canLoadEarlierRoutes,
                                action: actions.loadEarlierRoutes)
                routePageButton(title: "Later", systemImage: "chevron.down",
                                isLoading: viewModel.isLoadingLaterRoutes,
                                isEnabled: viewModel.canLoadLaterRoutes,
                                action: actions.loadLaterRoutes)
            }
        }

        if !viewModel.supplementalRouteOptions.isEmpty {
            Section("Other options") {
                ForEach(viewModel.supplementalRouteOptions) { option in
                    RouteOptionRow(option: option, isSelected: option.id == viewModel.selectedRouteOptionID)
                }
            }
        }
    }

    private func routePageButton(
        title: LocalizedStringKey, systemImage: String,
        isLoading: Bool, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                if isLoading {
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            }
        }
        .disabled(!isEnabled || viewModel.isLoadingEarlierRoutes || viewModel.isLoadingLaterRoutes)
    }
}
