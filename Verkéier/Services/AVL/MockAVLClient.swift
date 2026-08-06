import Foundation

struct MockAVLClient: AVLClient {
    var messages: [AlertMessage] = AVLPreviewFixtures.messages

    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        messages
    }
}

enum AVLPreviewFixtures {
    static let messages = [
        AlertMessage(
            id: "avl-general-1",
            title: "AVL network message",
            body: "Sample disruption message for development. Replace with live AVL emergency messages once the exact feed is confirmed.",
            severity: .warning,
            affectedStopIds: [],
            affectedRouteIds: ["16"],
            startsAt: nil,
            endsAt: nil,
            dataSource: .avl
        )
    ]
}
