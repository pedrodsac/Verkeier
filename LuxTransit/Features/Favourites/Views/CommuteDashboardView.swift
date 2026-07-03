import SwiftUI

struct CommuteDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DisplayStyle {
        case regular
        case mapsMedium
    }

    let viewModel: CommuteDashboardViewModel
    var displayStyle: DisplayStyle = .regular
    let actions: CommuteActions

    var body: some View {
        VStack(alignment: .leading, spacing: displayStyle == .mapsMedium ? 18 : 16) {
            if viewModel.activeAlertCount > 0 {
                AlertsSummaryRow(alertCount: viewModel.activeAlertCount, action: actions.showAlerts)
            }

            if let preset = viewModel.suggestedCommutePreset {
                CommuteSuggestionRow(preset: preset) { actions.applyCommutePreset(preset.id) }
            }

            if viewModel.hasFavourites {
                favouritesContent
            } else {
                emptyFavouritesContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favouritesContent: some View {
        Group {
            if viewModel.isLoadingDepartures, viewModel.departuresByStopId.isEmpty {
                DepartureLoadingCard(title: "Loading favourite departures")
            } else if let errorMessage = viewModel.errorMessage {
                CompactUnavailableCard(
                    title: "Favourite departures unavailable", message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                )
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.favourites) { stop in
                        FavouriteStopDepartureCard(
                            stop: stop,
                            departures: viewModel.departuresByStopId[stop.id] ?? [],
                            isExpanded: viewModel.expandedStopIds.contains(stop.id),
                            selectStop: { actions.selectStop(stop) },
                            toggleExpansion: { actions.toggleExpansion(stop.id) }
                        )
                    }

                    if !viewModel.recentStops.isEmpty {
                        DisclosureGroup("Recent") {
                            recentStopRows
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(.secondary)
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.bottom, 72)
            }
        }
    }

    private var emptyFavouritesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.nearby.isLoading, viewModel.nearby.stops.isEmpty {
                    DepartureLoadingCard(title: "Finding nearby stops")
                } else if let errorMessage = viewModel.nearby.errorMessage {
                    CompactUnavailableCard(
                        title: "Nearby stops unavailable", message: errorMessage,
                        systemImage: "location.slash"
                    )
                } else if viewModel.nearby.stops.isEmpty {
                    CompactUnavailableCard(
                        title: "No nearby stops", message: "Use search to find and save a stop.",
                        systemImage: "mappin.slash"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.nearby.stops.prefix(5)) { stop in
                            StopListRow(
                                stop: stop,
                                markerColor: .blue,
                                referenceLocation: viewModel.nearby.referenceLocation
                            ) {
                                actions.selectStop(stop)
                            }
                        }

                        Text("Tap a stop to see departures and save it to your commute.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .padding(.horizontal, 4)
                    }
                }

                if !viewModel.recentStops.isEmpty {
                    Text("Recent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                    recentStopRows
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var recentStopRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.recentStops.prefix(8)) { stop in
                StopListRow(
                    stop: stop,
                    markerColor: .blue,
                    referenceLocation: viewModel.nearby.referenceLocation
                ) {
                    actions.selectStop(stop)
                }
            }
        }
    }
}
