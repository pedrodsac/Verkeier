import SwiftUI

struct CommuteDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DisplayStyle {
        case regular
        case mapsMedium
    }

    let viewModel: CommuteDashboardViewModel
    let openSpecialEvent: (SpecialEvent) -> Void
    var displayStyle: DisplayStyle = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: displayStyle == .mapsMedium ? 18 : 16) {
            if viewModel.activeAlertCount > 0 {
                AlertsSummaryRow(alertCount: viewModel.activeAlertCount)
            }

            ForEach(viewModel.specialEvents) { event in
                SpecialEventRow(event: event) {
                    openSpecialEvent(event)
                }
            }

            if let preset = viewModel.suggestedCommutePreset {
                CommuteSuggestionRow(preset: preset)
            }

            stopsContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stopsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 4)

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
                stopGrid(
                    viewModel.nearby.stops.prefix(6),
                    routesByStopID: viewModel.nearby.routesByStopId
                )

                Text("Tap a stop to see departures and save it to your commute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .padding(.horizontal, 4)
            }

            if !viewModel.recentStops.isEmpty {
                Text("Recent Stops")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.horizontal, 4)

                stopGrid(viewModel.recentStops)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func stopGrid(
        _ stops: some Collection<Stop>,
        routesByStopID: [String: [TransitRoute]] = [:]
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(Array(stops)) { stop in
                StopListRow(
                    stop: stop,
                    markerColor: .blue,
                    accessorySystemName: nil,
                    referenceLocation: viewModel.nearby.referenceLocation,
                    routes: routesByStopID[stop.id] ?? [],
                    navigationValue: .stopDetail(stop)
                )
            }
        }
    }
}
