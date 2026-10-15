import SwiftUI

/// A slim pill shown above the results list while routes are being refreshed.
struct RouteInfoBanner: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.65), in: Capsule())
    }
}
