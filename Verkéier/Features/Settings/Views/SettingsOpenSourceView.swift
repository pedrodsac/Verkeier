import SwiftUI

struct SettingsOpenSourceView: View {
    private let libraries = [
        OpenSourceLibrary(
            name: "ZIPFoundation",
            url: URL(string: "https://github.com/weichsel/ZIPFoundation")!
        ),
        OpenSourceLibrary(
            name: "Swift Async Algorithms",
            url: URL(string: "https://github.com/apple/swift-async-algorithms")!
        ),
        OpenSourceLibrary(
            name: "Swift Collections",
            url: URL(string: "https://github.com/apple/swift-collections")!
        ),
        OpenSourceLibrary(
            name: "UIOnboarding",
            url: URL(string: "https://github.com/lascic/UIOnboarding")!
        )
    ]

    var body: some View {
        List {
            Section("Libraries") {
                ForEach(libraries) { library in
                    Link(destination: library.url) {
                        HStack {
                            Text(library.name)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Open-source")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct OpenSourceLibrary: Identifiable {
    let name: String
    let url: URL

    var id: String { name }
}

#Preview {
    NavigationStack {
        SettingsOpenSourceView()
    }
}
