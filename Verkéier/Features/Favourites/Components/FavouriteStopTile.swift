import SwiftUI

struct FavouriteStopTile: View {
    let favourite: FavouriteStopPresentationModel
    let actions: FavouritesActions
    let editLabels: () -> Void

    private var stop: Stop { favourite.stop }
    private var mode: TransportMode { stop.modes.primaryMode }

    var body: some View {
        Button(action: openStop) {
            tileContent
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens departures for this stop")
        .accessibilityAction(named: planToActionLabel) {
            actions.planTo(stop)
        }
        .accessibilityAction(named: planFromActionLabel) {
            actions.planFrom(stop)
        }
        .accessibilityAction(named: refreshActionLabel) {
            Task { await actions.refreshStop(stop) }
        }
        .accessibilityAction(named: editLabelsActionLabel, editLabels)
        .accessibilityAction(named: removeActionLabel) {
            actions.removeFavourite(stop.id)
        }
        .contextMenu {
            contextMenuActions
        }
    }

    private var tileContent: some View {
        VStack(spacing: 12) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            Text(verbatim: stop.displayName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            mode.tint.gradient,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
    }

    private func openStop() {
        actions.openStop(stop)
    }

    private var accessibilityLabel: String {
        "\(stop.displayName), \(mode.displayName)"
    }

    private var planToActionLabel: String {
        "Plan to \(stop.displayName)"
    }

    private var planFromActionLabel: String {
        "Plan from \(stop.displayName)"
    }

    private var refreshActionLabel: String {
        "Refresh departures for \(stop.displayName)"
    }

    private var editLabelsActionLabel: String {
        "Edit labels for \(stop.displayName)"
    }

    private var removeActionLabel: String {
        "Remove \(stop.displayName) from favourites"
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
}
