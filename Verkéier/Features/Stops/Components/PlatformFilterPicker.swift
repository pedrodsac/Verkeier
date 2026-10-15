import SwiftUI

/// Filters a stop's departures to one platform.
struct PlatformFilterPicker: View {
    let platforms: [String]
    let selectedPlatform: String?
    let selectPlatform: (String?) -> Void

    var body: some View {
        if !platforms.isEmpty {
            Picker(
                "Platform",
                selection: Binding(
                    get: { selectedPlatform ?? "" },
                    set: { selectPlatform($0.isEmpty ? nil : $0) }
                )
            ) {
                Text("All").tag("")
                ForEach(platforms, id: \.self) { platform in
                    Text(platform).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Platform filter")
        }
    }
}
