import Foundation
import Testing
@testable import Verkeier

struct ATPRequestBuilderTests {
    @Test func nearbyStopsURLContainsAccessIdAndRequiredParameters() throws {
        let url = try ATPRequestBuilder.nearbyStopsURL(
            latitude: 49.6116,
            longitude: 6.1319,
            configuration: configuration(accessId: "secret")
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = queryItems(from: components)

        #expect(url.path.hasSuffix("/location.nearbystops"))
        #expect(query["accessId"] == "secret")
        #expect(query["originCoordLat"] == "49.6116")
        #expect(query["originCoordLong"] == "6.1319")
        #expect(query["maxNo"] == "50")
        #expect(query["r"] == "1500")
        #expect(query["type"] == "SE")
        #expect(query["format"] == "json")
    }

    @Test func departureBoardURLContainsStopAndLanguageParameters() throws {
        let url = try ATPRequestBuilder.departureBoardURL(
            stopId: "200405060",
            configuration: configuration(accessId: "secret")
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = queryItems(from: components)

        #expect(url.path.hasSuffix("/departureBoard"))
        #expect(query["accessId"] == "secret")
        #expect(query["id"] == "200405060")
        #expect(query["lang"] == "fr")
        #expect(query["format"] == "json")
    }

    @Test func missingAccessIdFailsBeforeNetworkRequest() {
        #expect(throws: ATPClientError.missingAccessId) {
            _ = try ATPRequestBuilder.departureBoardURL(
                stopId: "200405060",
                configuration: configuration(accessId: nil)
            )
        }
    }

    @Test func proxyURLUsesWorkerRouteWithoutForwardingAccessId() throws {
        let url = try ATPRequestBuilder.departureBoardURL(
            stopId: "200405060",
            configuration: AppConfiguration(
                atpAccessId: nil,
                apiBaseURL: URL(string: "https://example.com/opendata/apiserver")!,
                avlMessagesURL: URL(string: "https://example.com/messages.xml")!,
                apiProxyURL: URL(string: "https://proxy.example.com")!
            )
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = queryItems(from: components)

        #expect(url.path == "/atp/departureBoard")
        #expect(query["accessId"] == nil)
        #expect(query["id"] == "200405060")
    }

    private func configuration(accessId: String?) -> AppConfiguration {
        AppConfiguration(
            atpAccessId: accessId,
            apiBaseURL: URL(string: "https://example.com/opendata/apiserver")!,
            avlMessagesURL: URL(string: "https://example.com/messages.xml")!
        )
    }

    private func queryItems(from components: URLComponents) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
