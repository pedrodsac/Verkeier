import Foundation
import Testing

@testable import LuxTransit

struct ATPClientTests {
    @Test func defaultCombinedDepartureBoardFetchesUniquePlatformIdsAndSorts() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = StubATPClient(boards: [
            "platform-1": [
                Departure(
                    id: "later",
                    stopId: "platform-1",
                    lineName: "15",
                    destination: "Hollerich",
                    scheduledDeparture: now.addingTimeInterval(240),
                    dataSource: .atpOpenAPI
                )
            ],
            "platform-2": [
                Departure(
                    id: "earlier",
                    stopId: "platform-2",
                    lineName: "10",
                    destination: "Gare",
                    scheduledDeparture: now.addingTimeInterval(60),
                    dataSource: .atpOpenAPI
                )
            ],
        ])

        let departures = try await client.departureBoards(stopIds: [
            "platform-1",
            "platform-2",
            "platform-1",
        ])

        #expect(departures.map(\.id) == ["earlier", "later"])
    }
}

private struct StubATPClient: ATPClient {
    let boards: [String: [Departure]]

    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId: String) async throws -> [Departure] {
        boards[stopId] ?? []
    }
}
