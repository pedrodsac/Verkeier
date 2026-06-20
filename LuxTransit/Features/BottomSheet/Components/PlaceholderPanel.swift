import SwiftUI

struct PlaceholderPanel: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
            }

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PlaceholderPanel(
        title: "Favourites",
        systemImage: "star.fill",
        message: "Your saved stops will appear here."
    )
}
