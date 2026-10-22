import SwiftData
import SwiftUI

/// The departure followed by a Live Activity or reminder, with buttons to stop either.
struct DepartureTrackingStatusCard: View {
    let trackedDeparture: Departure?
    let activeReminder: SharedTrackedDepartureReminder?
    let stopTrackingDeparture: () -> Void
    let cancelDepartureReminder: () -> Void

    var body: some View {
        if trackedDeparture != nil || activeReminder != nil {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let trackedDeparture {
                HStack(alignment: .top, spacing: 10) {
                    Label(
                        "Live Activity tracking \(trackedDeparture.lineName) to \(trackedDeparture.displayDestination)",
                        systemImage: "livephoto"
                    )
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Stop", action: stopTrackingDeparture)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }

            if let activeReminder {
                HStack(alignment: .top, spacing: 10) {
                    Label(
                        "Reminder set for \(activeReminder.leadTimeMinutes) min before \(activeReminder.lineName) to \(activeReminder.destination)",
                        systemImage: "bell.badge.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Cancel", action: cancelDepartureReminder)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
