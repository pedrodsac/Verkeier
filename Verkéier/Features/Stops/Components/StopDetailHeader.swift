import SwiftUI

/// The platform picker, line filter and Directions button above a stop's departures.
struct StopDetailHeader: View {
    let routes: [TransitRoute]
    let selectedLine: String?
    let showDirections: () -> Void
    let toggleDepartureLine: (TransitRoute) -> Void

    let availablePlatforms: [String]
    let selectedPlatform: String?
    let selectDeparturePlatform: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !availablePlatforms.isEmpty {
                PlatformFilterPicker(
                    platforms: availablePlatforms,
                    selectedPlatform: selectedPlatform,
                    selectPlatform: selectDeparturePlatform
                )
            }

            LineFilterSection(
                routes: routes,
                selectedLine: selectedLine,
                toggleDepartureLine: toggleDepartureLine
            )

            DirectionsButton(action: showDirections)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DirectionsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.blue, in: Capsule())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get directions")
    }
}
