import SwiftUI

struct TransitBottomSheet: View {
    @Binding var searchQuery: String
    let detent: BottomSheetDetent
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

    var body: some View {
        NavigationStack {
            BottomSheetContent(
                viewModel: viewModel,
                searchQuery: $searchQuery,
                detent: detent,
                actions: actions
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .toolbarVisibility(shouldHideNavigationBar ? .hidden : .visible, for: .navigationBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(viewModel.context.accessibilityLabel)
        }
    }

    private var shouldHideNavigationBar: Bool {
        detent == .collapsed || viewModel.context == .search
            || (detent == .medium && viewModel.context == .home)
    }

    private var navigationTitle: String {
        switch viewModel.context {
        case .home:
            viewModel.commute.hasFavourites ? "Commute" : "Nearby"
        case .search:
            "Search"
        case .stopDetail:
            viewModel.stopDetail.stop?.name ?? "Selected Stop"
        case .directions:
            "Directions"
        case .routeTimeline:
            "Selected route"
        case .lineDetail:
            viewModel.lineDetail.route?.shortName ?? "Line details"
        case .alerts:
            "Service Alerts"
        case .settings:
            "Settings"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch viewModel.context {
        case .home:
            if viewModel.commute.activeAlertCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: actions.showAlerts) {
                        Label("Show alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                    .tint(.orange)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.showSettings) {
                    Label("Settings and diagnostics", systemImage: "gearshape")
                }
            }

        case .search:
            ToolbarItem(placement: .topBarTrailing) {
                EmptyView()
            }

        case .stopDetail:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close stop details", systemImage: "chevron.down")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                let isFavourite = viewModel.stopDetail.isFavourite
                Button(action: actions.toggleFavourite) {
                    Label(
                        isFavourite ? "Remove favourite" : "Save favourite",
                        systemImage: isFavourite ? "star.fill" : "star"
                    )
                }
                .tint(isFavourite ? .yellow : nil)
            }

        case .directions:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showStopDetail) {
                    Label("Back to stop", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                RoutePlanningTimeButton(
                    current: viewModel.route.planningTime,
                    onChange: actions.setRoutePlanningTime
                )
            }

        case .routeTimeline:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showRouteOptions) {
                    Label("Back to route options", systemImage: "chevron.left")
                }
            }

        case .lineDetail:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showStopDetail) {
                    Label("Back to stop", systemImage: "chevron.left")
                }
            }

        case .alerts:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close alerts", systemImage: "chevron.down")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.refreshAlerts) {
                    Label("Refresh alerts", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.alerts.isLoading)
            }

        case .settings:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.showHome) {
                    Label("Close settings", systemImage: "chevron.down")
                }
            }
        }
    }
}

// MARK: - Route planning time

/// Toolbar calendar menu for choosing when to travel. A menu offers
/// "Leave now / Leave at… / Arrive by…"; the latter two open a sheet to pick the
/// time.
private struct RoutePlanningTimeButton: View {
    let current: RoutePlanningTime
    let onChange: (RoutePlanningTime) -> Void

    @State private var editing: Mode?
    @State private var date: Date = .now

    private enum Mode: Identifiable {
        case leave, arrive
        var id: Int {
            self == .leave ? 0 : 1
        }

        var title: String {
            self == .leave ? "Leave at" : "Arrive by"
        }

        func planningTime(_ date: Date) -> RoutePlanningTime {
            self == .leave ? .departAt(date) : .arriveBy(date)
        }
    }

    var body: some View {
        Menu {
            Button {
                onChange(.leaveNow)
            } label: {
                Label("Leave now", systemImage: current.isNow ? "checkmark" : "clock")
            }
            Button {
                date = current.date ?? .now
                editing = .leave
            } label: {
                Label("Leave at…", systemImage: "calendar")
            }
            Button {
                date = current.date ?? .now
                editing = .arrive
            } label: {
                Label("Arrive by…", systemImage: "flag.checkered")
            }
        } label: {
            Label(
                "Choose travel time",
                systemImage: current.isNow ? "calendar" : "calendar.badge.clock"
            )
        }
        .tint(current.isNow ? nil : .blue)
        .sheet(item: $editing) { mode in
            NavigationStack {
                DatePicker(
                    "Time",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle(mode.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onChange(mode.planningTime(date))
                            editing = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
