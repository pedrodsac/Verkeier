import SwiftUI
import UIKit

struct CommuteDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DisplayStyle {
        case regular
        case mapsMedium
    }

    let viewModel: CommuteDashboardViewModel
    let favouritesViewModel: FavouritesPresentationModel
    let favouritesActions: FavouritesActions
    let openSpecialEvent: (SpecialEvent) -> Void
    var displayStyle: DisplayStyle = .regular

    @State private var editingFavourite: FavouriteStopPresentationModel?
    @State private var lastEditedFavouriteID: String?
    @AccessibilityFocusState private var focusedFavouriteID: String?

    var body: some View {
        List {
			if hasDashboardCards {
				if viewModel.activeAlertCount > 0 {
					Section {
						AlertsSummaryRow(alertCount: viewModel.activeAlertCount)
					}
					.listRowBackground(Color.orange.opacity(0.12))
				}

				Section {
                    ForEach(viewModel.specialEvents) { event in
                        SpecialEventRow(event: event) {
                            openSpecialEvent(event)
                        }
                    }

                    if let preset = viewModel.suggestedCommutePreset {
                        CommuteSuggestionRow(preset: preset)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if !favouritesViewModel.stops.isEmpty {
                favouritesSection
            }

            nearbySection

            if !viewModel.recentStops.isEmpty {
                recentsSection
            }
        }
        .listStyle(.insetGrouped)
		.scrollIndicators(.hidden)
        .sheet(item: $editingFavourite, onDismiss: restoreEditedFavouriteFocus) { favourite in
            FavouriteLabelsEditor(
                favourite: favourite,
                availableLabels: favouritesViewModel.availableLabels,
                save: { labels in
                    favouritesActions.updateLabels(favourite.stop.id, labels)
                }
            )
        }
    }

    private var favouritesSection: some View {
        carouselSection("Favourites") {
			stopCarousel(favouriteColumns, favorite: true) { favourite in
                favouriteStopRow(favourite)
            }
        }
    }

    @ViewBuilder
    private var nearbySection: some View {
        Section {
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
                stopCarousel(nearbyStopColumns) { stop in
                    stopNavigationRow(
                        stop,
                        routes: viewModel.nearby.routesByStopId[stop.id] ?? []
                    )
                }
            }
        } header: {
            Text("Nearby")
                .safeAreaPadding(.horizontal, 16)
        }
        .listSectionMargins(.horizontal, 0)
		.listRowSeparator(.hidden)
    }

    private var recentsSection: some View {
        carouselSection("Recents") {
            stopCarousel(recentStopColumns) { stop in
                stopNavigationRow(stop)
            }
        }
    }

    private func carouselSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(title)
                .safeAreaPadding(.horizontal, 16)
        }
        .listSectionMargins(.horizontal, 0)
    }

    private func stopCarousel<Item, Row: View>(
        _ columns: [[Item]],
		favorite: Bool = false,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, items in
                    VStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { index in
                            row(items[index])

                            if index < items.index(before: items.endIndex) {
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in
                        width - 24
                    }
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 24, style: .continuous)
                    )
                }
            }
            .scrollTargetLayout()
            .background(FastScrollDecelerationConfigurator())
        }
        .safeAreaPadding(.horizontal, 16)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(CarouselColumnScrollTargetBehavior())
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func stopNavigationRow(_ stop: Stop, routes: [TransitRoute] = []) -> some View {
        NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
            carouselRowLabel(stop: stop, routes: routes)
        }
        .buttonStyle(.plain)
    }

    private func favouriteStopRow(_ favourite: FavouriteStopPresentationModel) -> some View {
        Button {
            favouritesActions.openStop(favourite.stop)
        } label: {
            carouselRowLabel(stop: favourite.stop)
        }
        .buttonStyle(.plain)
        .accessibilityFocused($focusedFavouriteID, equals: favourite.id)
        .accessibilityHint("Opens departures for this stop")
        .accessibilityAction(named: "Plan to \(favourite.stop.displayName)") {
            favouritesActions.planTo(favourite.stop)
        }
        .accessibilityAction(named: "Plan from \(favourite.stop.displayName)") {
            favouritesActions.planFrom(favourite.stop)
        }
        .contextMenu {
            favouriteContextMenu(for: favourite)
        }
    }

    private func carouselRowLabel(
        stop: Stop,
        routes: [TransitRoute] = []
    ) -> some View {
        HStack(spacing: 8) {
            StopRow(stop: stop, routes: routes)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var nearbyStopColumns: [[Stop]] {
        chunked(Array(viewModel.nearby.stops.prefix(6)))
    }

    private var favouriteColumns: [[FavouriteStopPresentationModel]] {
        chunked(favouritesViewModel.stops)
    }

    private var recentStopColumns: [[Stop]] {
        chunked(viewModel.recentStops)
    }

    private func chunked<Item>(_ items: [Item]) -> [[Item]] {
        stride(from: 0, to: items.count, by: 3).map { startIndex in
            Array(items[startIndex..<min(startIndex + 3, items.count)])
        }
    }

    private func restoreEditedFavouriteFocus() {
        guard let lastEditedFavouriteID else { return }
        Task { @MainActor in
            focusedFavouriteID = lastEditedFavouriteID
            self.lastEditedFavouriteID = nil
        }
    }

    @ViewBuilder
    private func favouriteContextMenu(for favourite: FavouriteStopPresentationModel) -> some View {
        let stop = favourite.stop
        Button {
            favouritesActions.openStop(stop)
        } label: {
            Label("Open departures", systemImage: "clock")
        }
        Button {
            favouritesActions.planTo(stop)
        } label: {
            Label("Plan to this stop", systemImage: "arrow.right.circle")
        }
        Button {
            favouritesActions.planFrom(stop)
        } label: {
            Label("Plan from this stop", systemImage: "arrow.left.circle")
        }
        Button {
            Task { await favouritesActions.refreshStop(stop) }
        } label: {
            Label("Refresh departures", systemImage: "arrow.clockwise")
        }
        Button {
            lastEditedFavouriteID = favourite.id
            editingFavourite = favourite
        } label: {
            Label("Edit labels", systemImage: "tag")
        }
        Divider()
        Button(role: .destructive) {
            favouritesActions.removeFavourite(stop.id)
        } label: {
            Label("Remove favourite", systemImage: "star.slash")
        }
    }

    private var hasDashboardCards: Bool {
        viewModel.activeAlertCount > 0
            || !viewModel.specialEvents.isEmpty
            || viewModel.suggestedCommutePreset != nil
    }
}

private struct CarouselColumnScrollTargetBehavior: ScrollTargetBehavior {
    private let viewAligned = ViewAlignedScrollTargetBehavior()

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        viewAligned.updateTarget(&target, context: context)

        let edgeTolerance: CGFloat = 1
        let columnRect = target.rect
        let maximumOffset = max(0, context.contentSize.width - context.containerSize.width)
        let proposedOffset: CGFloat

        if columnRect.minX <= edgeTolerance {
            proposedOffset = 0
        } else if columnRect.maxX >= context.contentSize.width - edgeTolerance {
            proposedOffset = maximumOffset
        } else {
            proposedOffset = columnRect.midX - (context.containerSize.width / 2)
        }

        target.rect.origin.x = min(max(0, proposedOffset), maximumOffset)
        target.anchor = .topLeading
    }
}

private struct FastScrollDecelerationConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        configureScrollView(containing: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        configureScrollView(containing: uiView)
    }

    private func configureScrollView(containing view: UIView) {
        DispatchQueue.main.async {
            var ancestor = view.superview

            while let currentView = ancestor {
                if let scrollView = currentView as? UIScrollView {
                    scrollView.decelerationRate = .fast
                    return
                }

                ancestor = currentView.superview
            }
        }
    }
}
