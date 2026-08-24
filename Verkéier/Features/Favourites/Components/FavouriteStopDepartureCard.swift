import SwiftUI

struct FavouriteStopDepartureCard: View {
	@State private var isExpanded: Bool = true

    let favourite: FavouriteStopPresentationModel
    let actions: FavouritesActions
    let editLabels: () -> Void

    private var stop: Stop { favourite.stop }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stopRow

            if !favourite.labels.isEmpty {
                labels
            }

            if isExpanded {
                departureContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Plan to \(stop.displayName)") {
            actions.planTo(stop)
        }
        .accessibilityAction(named: "Plan from \(stop.displayName)") {
            actions.planFrom(stop)
        }
        .accessibilityAction(named: "Refresh departures for \(stop.displayName)") {
            Task { await actions.refreshStop(stop) }
        }
        .accessibilityAction(named: "Edit labels for \(stop.displayName)", editLabels)
        .accessibilityAction(named: "Remove \(stop.displayName) from favourites") {
            actions.removeFavourite(stop.id)
        }
    }

    private var stopRow: some View {
        StopListRow(
            stop: stop,
            markerColor: .blue,
            accessorySystemName: isExpanded ? "chevron.down" : "chevron.right",
            surface: .favourite,
            accessoryAction: { isExpanded.toggle() },
            action: { actions.openStop(stop) }
        )
        .accessibilityLabel("Open departures for \(stop.displayName)")
        .contextMenu {
            contextMenuActions
        }
    }

    @ViewBuilder
    private var contextMenuActions: some View {
        Button {
            actions.openStop(stop)
        } label: {
            Label("Open departures", systemImage: "clock")
        }
        Button {
            actions.planTo(stop)
        } label: {
            Label("Plan to this stop", systemImage: "arrow.right.circle")
        }
        Button {
            actions.planFrom(stop)
        } label: {
            Label("Plan from this stop", systemImage: "arrow.left.circle")
        }
        Button {
            Task { await actions.refreshStop(stop) }
        } label: {
            Label("Refresh departures", systemImage: "arrow.clockwise")
        }
        Button(action: editLabels) {
            Label("Edit labels", systemImage: "tag")
        }
        Divider()
        Button(role: .destructive) {
            actions.removeFavourite(stop.id)
        } label: {
            Label("Remove favourite", systemImage: "star.slash")
        }
    }

    private var labels: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(favourite.labels, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Labels: \(favourite.labels.formatted())")
    }

    @ViewBuilder
    private var departureContent: some View {
        switch favourite.departures.phase {
        case .idle:
            EmptyView()

        case .loading where !favourite.departures.hasPreviousContent:
            DepartureLoadingCard(title: "Loading departures")

        case .loading, .loaded, .failed:
            if !favourite.departures.departures.isEmpty {
				ForEach(favourite.departures.departures.prefix(3)) { departure in
					DepartureListRow(departure: departure, showsControls: false)
				}
            } else if favourite.departures.phase == .loaded {
                CompactUnavailableCard(
                    title: "No upcoming departures",
                    message: "No live departures are currently available for this stop.",
                    systemImage: "clock.badge.exclamationmark"
                )
            } else if favourite.departures.phase == .failed {
                CompactUnavailableCard(
                    title: "Departures unavailable",
                    message: favourite.departures.errorMessage ?? "Live departures could not be loaded for this stop.",
                    systemImage: "wifi.exclamationmark"
                )
            }

//            if let errorMessage = favourite.departures.errorMessage {
//                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
//                    .font(.footnote)
//                    .foregroundStyle(.orange)
//                    .accessibilityLabel("Departure refresh failed. \(errorMessage)")
//            }

//            if favourite.departures.phase == .loading, favourite.departures.hasPreviousContent {
//                Label("Refreshing departures", systemImage: "arrow.clockwise")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//            }
        }
    }
}
