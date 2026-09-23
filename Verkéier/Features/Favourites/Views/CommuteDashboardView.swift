import SwiftUI

struct CommuteDashboardView: View {
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
		.listSectionSpacing(16)
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
			pagedListSection(favouritesViewModel.stops, favorite: true) { favourite in
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
                pagedListSection(Array(viewModel.nearby.stops.prefix(6))) { stop in
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
            pagedListSection(viewModel.recentStops) { stop in
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

    private func pagedListSection<Item, Row: View>(
        _ items: [Item],
		favorite: Bool = false,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
		PagedListSection(items: items, row: row, favorite: favorite)
            .listRowInsets(EdgeInsets())
			.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func stopNavigationRow(_ stop: Stop, routes: [TransitRoute] = []) -> some View {
        NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
            StopRow(stop: stop, routes: routes)
        }
    }

    private func favouriteStopRow(_ favourite: FavouriteStopPresentationModel) -> some View {
        Button {
            favouritesActions.openStop(favourite.stop)
        } label: {
            StopRow(stop: favourite.stop)
        }
		.foregroundStyle(.primary)
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

/// A horizontally paged sequence of native inset-grouped list sections.
///
/// A `Section` gets its grouped styling only when hosted by a `List`, so each
/// page owns a small, non-scrolling list rather than recreating rows manually.
private struct PagedListSection<Item, Row: View>: View {
    private let items: [Item]
    private let row: (Item) -> Row
    /// Leaves 16pt of the next inset-grouped section visible after accounting
    /// for that list's own 16pt leading margin.
    private let pagePeekWidth: CGFloat = 16

	@ScaledMetric(relativeTo: .body) private var standardRowHeight: CGFloat = 50
	@ScaledMetric(relativeTo: .body) private var sectionVerticalMargins: CGFloat = 50
	
	let favorite: Bool

	init(items: [Item], @ViewBuilder row: @escaping (Item) -> Row, favorite: Bool = false) {
        self.items = items
        self.row = row
		self.favorite = favorite
    }

    private var pages: [[Item]] {
        stride(from: 0, to: items.count, by: 3).map { startIndex in
            Array(items[startIndex..<min(startIndex + 3, items.count)])
        }
    }

    private var hasMultiplePages: Bool {
        pages.count > 1
    }

    private var pageSpacing: CGFloat {
        hasMultiplePages ? -16 : 0
    }

    private var pageWidthReduction: CGFloat {
        hasMultiplePages ? pagePeekWidth : 0
    }

    /// Three standard dashboard rows plus the native grouped-section margins.
    /// `@ScaledMetric` lets this grow alongside Dynamic Type.
    private var pageHeight: CGFloat {
        (standardRowHeight * 3) + sectionVerticalMargins
    }

    var body: some View {
        ScrollView(.horizontal) {
            // The overlap reclaims the inner lists' adjoining 16pt margins:
            // cards gain 16pt without losing the next-card preview. A lone
            // page uses the full width because there is nothing to preview.
            LazyHStack(spacing: pageSpacing) {
                ForEach(pages.indices, id: \.self) { index in
                    List {
                        Section {
                            ForEach(pages[index].indices, id: \.self) { itemIndex in
                                row(pages[index][itemIndex])
                            }
                        }
						.listRowBackground(favorite ? Color.yellow.opacity(0.12) : nil)
                    }
                    .listStyle(.insetGrouped)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    // The nested list otherwise adds a scroll-content inset
                    // above its section, leaving a gap below the outer header
                    // and consuming the space reserved for the third row.
                    .contentMargins(.top, 0, for: .scrollContent)
                    .frame(height: pageHeight)
                    .containerRelativeFrame(.horizontal) { width, _ in
                        max(0, width - pageWidthReduction)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: pageHeight)
        .scrollTargetBehavior(ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne))
        .scrollIndicators(.hidden)
    }
}
