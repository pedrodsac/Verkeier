import SwiftUI

/// The number of active disruptions, opening the alerts list.
struct AlertsSummaryRow: View {
    let alertCount: Int

    var body: some View {
        NavigationLink(value: SheetRoute.alerts) {
            Label {
                Text(alertText)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(alertText)
    }

    private var alertText: String {
        alertCount == 1 ? "1 active disruption" : "\(alertCount) active disruptions"
    }
}
