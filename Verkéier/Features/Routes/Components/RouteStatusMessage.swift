import SwiftUI

/// An inline info note shown below route results when a status message is set.
struct RouteStatusMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
