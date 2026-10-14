import SwiftData
import SwiftUI

/// The Home tab: disruptions, special events, the commute suggestion, then
/// favourite, nearby and recent stops.
struct CommuteDashboardView: View {
    @Environment(MapModel.self) private var map
    @Environment(SearchModel.self) private var search
    @Environment(AlertsModel.self) private var alerts
    @Environment(RoutePlannerModel.self) private var routePlanner
    @Environment(FavouritesModel.self) private var favourites
    @Environment(SheetRouter.self) private var router
    @Environment(\.liveTransitService) private var liveTransitService
    @Environment(\.gtfsService) private var gtfsService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistedFavouriteStop.createdAt) private var favouriteStops: [PersistedFavouriteStop]

    @State private var editingFavourite: PersistedFavouriteStop?
    @State private var lastEditedFavouriteID: String?
    @AccessibilityFocusState private var focusedFavouriteID: String?

    var body: some View {
        let specialEvents = SpecialEventCatalog.activeEvents()
        let recentStops = search.distinctRecentStops

        List {
            if alerts.activeAlertCount > 0 || !specialEvents.isEmpty || routePlanner.suggestedCommutePreset != nil {
                dashboardCards(specialEvents: specialEvents)
            }

            if !favouriteStops.isEmpty {
                favouritesSection
            }

            nearbySection

            if !recentStops.isEmpty {
                recentsSection(recentStops)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .scrollIndicators(.hidden)
        .sheet(item: $editingFavourite, onDismiss: restoreEditedFavouriteFocus) { favourite in
            FavouriteCustomizerView(
                stop: favourite.stop,
                initialLabel: favourite.displayLabel,
                initialColorHex: favourite.colorHex,
                initialIconName: favourite.iconName
            ) { label, colorHex, iconName in
                favourites.updateAppearance(
                    stopID: favourite.stopId,
                    label: label,
                    colorHex: colorHex,
                    iconName: iconName,
                    in: modelContext
                )
            }
        }
    }
}

// MARK: - Sections

private extension CommuteDashboardView {
    @ViewBuilder
    func dashboardCards(specialEvents: [SpecialEvent]) -> some View {
        if alerts.activeAlertCount > 0 {
            Section {
                AlertsSummaryRow(alertCount: alerts.activeAlertCount)
            }
            .listRowBackground(Color.orange.opacity(0.12))
        }

        Section {
            ForEach(specialEvents) { event in
                // TODO: Open the event's stop. The lookup was lost in a581393, so this does nothing yet.
                SpecialEventRow(event: event) {}
            }

            if let preset = routePlanner.suggestedCommutePreset {
                CommuteSuggestionRow(preset: preset)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    var favouritesSection: some View {
        carouselSection("Favourites") {
            pagedListSection(favouriteStops, favorite: true) { favourite in
                favouriteRow(favourite)
            }
        }
    }

    var nearbySection: some View {
        Section {
            let nearbyStops = map.distinctNearbyStops
            if map.isLoadingNearbyStops, nearbyStops.isEmpty {
                DepartureLoadingCard(title: "Finding nearby stops")
            } else if let errorMessage = map.nearbyStopsErrorMessage {
                CompactUnavailableCard(
                    title: "Nearby stops unavailable",
                    message: errorMessage,
                    systemImage: "location.slash"
                )
            } else if nearbyStops.isEmpty {
                CompactUnavailableCard(
                    title: "No nearby stops",
                    message: "Use search to find and save a stop.",
                    systemImage: "mappin.slash"
                )
            } else {
                pagedListSection(Array(nearbyStops.prefix(6))) { stop in
                    stopNavigationRow(stop, routes: map.nearbyStopRoutes[stop.id] ?? [])
                }
            }
        } header: {
            Text("Nearby")
                .safeAreaPadding(.horizontal, 16)
        }
        .listSectionMargins(.horizontal, 0)
        .listRowSeparator(.hidden)
    }

    func recentsSection(_ recentStops: [Stop]) -> some View {
        carouselSection("Recents") {
            pagedListSection(recentStops) { stop in
                stopNavigationRow(stop)
            }
        }
    }

    func carouselSection<Content: View>(
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

    func pagedListSection<Item, Row: View>(
        _ items: [Item],
        favorite: Bool = false,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        PagedListSection(items: items, row: row, favorite: favorite)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Rows

private extension CommuteDashboardView {
    func stopNavigationRow(_ stop: Stop, routes: [TransitRoute] = []) -> some View {
        NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
            StopRow(stop: stop, routes: routes)
        }
    }

    func favouriteRow(_ favourite: PersistedFavouriteStop) -> some View {
        let stop = favourite.stop
        return Button {
            openStop(stop)
        } label: {
            StopRow(
                stop: stop,
                markerColor: favourite.colorHex.map { Color(hex: $0) } ?? stop.modes.primaryMode.tint,
                title: favourite.displayLabel ?? stop.displayName,
                subtitle: stop.modes.contains(.train) ? stop.displaySubtitle : stop.fullName,
                iconName: favourite.iconName
            )
        }
        .foregroundStyle(.primary)
        .accessibilityFocused($focusedFavouriteID, equals: favourite.stopId)
        .accessibilityHint("Opens departures for this stop")
        .accessibilityAction(named: "Plan to \(stop.displayName)") {
            router.planRoute(to: stop)
        }
        .accessibilityAction(named: "Plan from \(stop.displayName)") {
            router.planRoute(from: stop)
        }
        .contextMenu {
            favouriteContextMenu(for: favourite, stop: stop)
        }
    }

    @ViewBuilder
    func favouriteContextMenu(for favourite: PersistedFavouriteStop, stop: Stop) -> some View {
        Button {
            openStop(stop)
        } label: {
            Label("Open departures", systemImage: "clock")
        }
        Button {
            router.planRoute(to: stop)
        } label: {
            Label("Plan to this stop", systemImage: "arrow.right.circle")
        }
        Button {
            router.planRoute(from: stop)
        } label: {
            Label("Plan from this stop", systemImage: "arrow.left.circle")
        }
        Button {
            Task {
                await favourites.refreshFavouriteDeparture(
                    stop: stop,
                    using: liveTransitService,
                    gtfsService: gtfsService
                )
            }
        } label: {
            Label("Refresh departures", systemImage: "arrow.clockwise")
        }
        Button {
            lastEditedFavouriteID = favourite.stopId
            editingFavourite = favourite
        } label: {
            Label("Customize favourite", systemImage: "paintpalette")
        }
        Divider()
        Button(role: .destructive) {
            favourites.remove(stopID: stop.id, in: modelContext)
        } label: {
            Label("Remove favourite", systemImage: "star.slash")
        }
    }
}

// MARK: - Helpers

private extension CommuteDashboardView {
    func openStop(_ stop: Stop) {
        router.show([.stopDetail(stop)], detent: .medium)
    }

    func restoreEditedFavouriteFocus() {
        guard let lastEditedFavouriteID else { return }
        Task { @MainActor in
            focusedFavouriteID = lastEditedFavouriteID
            self.lastEditedFavouriteID = nil
        }
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
