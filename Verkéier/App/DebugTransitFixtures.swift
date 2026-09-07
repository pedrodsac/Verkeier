import Foundation

struct FailingAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        throw AVLClientError.invalidResponse
    }
}

struct EmptyAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        []
    }
}

struct SevereMockAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        [
            AlertMessage(
                id: "severe-1",
                title: "Major disruption on T1 and line 4",
                body: "Luxembourg city centre services are severely disrupted. Expect cancellations and long transfer delays.",
                severity: .severe,
                affectedStopIds: ["sample-hamilius"],
                affectedRouteIds: ["4", "T1"],
                startsAt: .now,
                endsAt: nil,
                dataSource: .mock
            )
        ]
    }
}
