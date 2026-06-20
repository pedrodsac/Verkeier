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

    @Test func liveClientDecodesConcurrentPlatformBoardsIndependently() async throws {
        ATPClientURLProtocol.responsesByStopId = [
            "platform-1": departureBoardJSON(id: "one", stopId: "platform-1", line: "10"),
            "platform-2": departureBoardJSON(id: "two", stopId: "platform-2", line: "11"),
            "platform-3": departureBoardJSON(id: "three", stopId: "platform-3", line: "12"),
        ]
        defer {
            ATPClientURLProtocol.responsesByStopId = [:]
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ATPClientURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = LiveATPClient(
            configuration: AppConfiguration(
                atpAccessId: "test-access-id",
                apiBaseURL: URL(string: "https://example.com/opendata/apiserver")!,
                avlMessagesURL: URL(string: "https://example.com/alerts.xml")!
            ),
            session: session
        )

        let departures = try await client.departureBoards(stopIds: [
            "platform-1",
            "platform-2",
            "platform-3",
        ])

        #expect(Set(departures.map(\.stopId)) == ["platform-1", "platform-2", "platform-3"])
        #expect(Set(departures.map(\.lineName)) == ["10", "11", "12"])
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

private final class ATPClientURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responsesByStopId: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stopId = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "id" }?
            .value ?? ""
        let body = Self.responsesByStopId[stopId] ?? #"{"Departure":[]}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func departureBoardJSON(id: String, stopId: String, line: String) -> String {
    """
    {
      "Departure": [
        {
          "name": "Bus \(line)",
          "type": "BUS",
          "stop": "Test Stop",
          "stopid": "\(stopId)",
          "stopExtId": "\(stopId)",
          "time": "10:00:00",
          "date": "2026-06-13",
          "direction": "Central",
          "platform": "1",
          "cancelled": false,
          "Product": {
            "name": "Bus \(line)",
            "line": "\(line)",
            "catOutL": "Bus",
            "operator": "Test Operator"
          }
        }
      ]
    }
    """
}
