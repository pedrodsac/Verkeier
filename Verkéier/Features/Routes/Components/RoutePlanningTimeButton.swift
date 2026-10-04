import SwiftUI

/// Toolbar menu for choosing whether a trip leaves now, departs later, or
/// needs to arrive by a chosen time.
struct RoutePlanningTimeButton: View {
    let current: RoutePlanningTime
    let onChange: (RoutePlanningTime) -> Void

    @State private var editing: Mode?
    @State private var date: Date = .now
    @AccessibilityFocusState private var isTimeButtonFocused: Bool

    private enum Mode: Identifiable {
        case leave
        case arrive

        var id: Self { self }

        var title: String {
            switch self {
            case .leave: "Leave at"
            case .arrive: "Arrive by"
            }
        }

        func planningTime(_ date: Date) -> RoutePlanningTime {
            switch self {
            case .leave: .departAt(date)
            case .arrive: .arriveBy(date)
            }
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
                date = max(current.date ?? .now, .now)
                editing = .leave
            } label: {
                Label("Leave at…", systemImage: "calendar")
            }
            Button {
                date = max(current.date ?? .now, .now)
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
        .accessibilityValue(timeDescription)
        .accessibilityFocused($isTimeButtonFocused)
        .sheet(item: $editing, onDismiss: restoreTimeButtonFocus) { mode in
            NavigationStack {
                DatePicker(
                    "Time",
                    selection: $date,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle(mode.title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onChange(mode.planningTime(date).confirmedPickerTime(now: .now))
                            editing = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var timeDescription: String {
        switch current {
        case .leaveNow: String(localized: "Leave now")
        case let .departAt(date): String(localized: "Leave at \(date.formatted(date: .abbreviated, time: .shortened))")
        case let .arriveBy(date): String(localized: "Arrive by \(date.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    private func restoreTimeButtonFocus() {
        Task { @MainActor in
            isTimeButtonFocused = true
        }
    }
}
