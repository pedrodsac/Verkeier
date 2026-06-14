import SwiftUI

struct CommuteDashboardView: View {
    let viewModel: CommuteDashboardViewModel
    let showAlerts: () -> Void
    let selectStop: (Stop) -> Void
    let toggleExpansion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.hasFavourites ? viewModel.statusText : "Stops around you")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.activeAlertCount > 0 {
                AlertsSummaryRow(alertCount: viewModel.activeAlertCount, action: showAlerts)
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
            if viewModel.isLoadingDepartures && viewModel.departuresByStopId.isEmpty {
                DepartureLoadingCard(title: "Loading favourite departures")
            } else if let errorMessage = viewModel.errorMessage {
                CompactUnavailableCard(
                    title: "Favourite departures unavailable", message: errorMessage,
                    systemImage: "wifi.exclamationmark")
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.favourites) { stop in
                        FavouriteStopDepartureCard(
                            stop: stop,
                            departures: viewModel.departuresByStopId[stop.id] ?? [],
                            isExpanded: viewModel.expandedStopIds.contains(stop.id),
                            selectStop: { selectStop(stop) },
                            toggleExpansion: { toggleExpansion(stop.id) }
                        )
                    }
                }
                .padding(.bottom, 72)
            }
        }
    }

    private var emptyFavouritesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.nearby.isLoading && viewModel.nearby.stops.isEmpty {
                DepartureLoadingCard(title: "Finding nearby stops")
            } else if let errorMessage = viewModel.nearby.errorMessage {
                CompactUnavailableCard(
                    title: "Nearby stops unavailable", message: errorMessage,
                    systemImage: "location.slash")
            } else if viewModel.nearby.stops.isEmpty {
                CompactUnavailableCard(
                    title: "No nearby stops", message: "Use search to find and save a stop.",
                    systemImage: "mappin.slash")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.nearby.stops.prefix(5)) { stop in
                            StopListRow(stop: stop, markerColor: .blue) {
                                selectStop(stop)
                            }
                        }

                        Text("Tap a stop to see departures and save it to your commute.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .padding(.horizontal, 4)
                    }
                    .padding(.bottom, 72)
                }
            }
        }
    }
}

struct AlertsSummaryRow: View {
    let alertCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(alertText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                .orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alertText)
    }

    private var alertText: String {
        alertCount == 1 ? "1 active disruption" : "\(alertCount) active disruptions"
    }
}

struct FavouriteStopDepartureCard: View {
    let stop: Stop
    let departures: [Departure]
    let isExpanded: Bool
    let selectStop: () -> Void
    let toggleExpansion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: selectStop) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(transitColor.gradient, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(stop.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(primarySummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let secondarySummary {
                            Text(secondarySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Button(action: toggleExpansion) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse departures" : "Expand departures")
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    Divider().padding(.leading, 62)
                    if departures.isEmpty {
                        Text("No live departures available")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(departures.prefix(3)) { departure in
                            DepartureListRow(departure: departure, showsTrackButton: false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .background(
            .background.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.22), lineWidth: 0.5)
        }
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private var primarySummary: String {
        guard let departure = departures.first else {
            return stop.locality ?? "Tap to view departures"
        }
        return "\(departure.lineName) \(departure.destination) · \(departure.status.displayText)"
    }

    private var secondarySummary: String? {
        guard departures.count > 1 else { return nil }
        let departure = departures[1]
        return "\(departure.lineName) \(departure.destination) · \(departure.status.displayText)"
    }

    private var iconName: String {
        if stop.modes.contains(.train) { return "train.side.front.car" }
        if stop.modes.contains(.tram) { return "tram.fill" }
        if stop.modes.contains(.funicular) { return "cablecar.fill" }
        return "bus.fill"
    }

    private var transitColor: Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return .blue
    }
}
