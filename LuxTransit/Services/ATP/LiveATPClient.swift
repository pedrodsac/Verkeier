import Foundation

final class LiveATPClient: ATPClient, @unchecked Sendable {
    private let configuration: AppConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        configuration: AppConfiguration = .current,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
    }

    func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        let request = try URLRequest(url: ATPRequestBuilder.nearbyStopsURL(
            latitude: latitude,
            longitude: longitude,
            configuration: configuration
        ))
        let response: ATPNearbyStopsResponse = try await fetch(request)
        return ATPMapper.mapNearbyStops(response)
    }

    func departureBoard(stopId: String) async throws -> [Departure] {
        let request = try URLRequest(url: ATPRequestBuilder.departureBoardURL(
            stopId: stopId,
            configuration: configuration
        ))
        let response: ATPDepartureBoardResponse = try await fetch(request)
        return ATPMapper.mapDepartures(response, stopId: stopId)
    }

    private func fetch<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATPClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ATPClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

enum ATPRequestBuilder {
    static func nearbyStopsURL(
        latitude: Double,
        longitude: Double,
        configuration: AppConfiguration
    ) throws -> URL {
        try url(
            path: "location.nearbystops",
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "originCoordLat", value: String(latitude)),
                URLQueryItem(name: "originCoordLong", value: String(longitude)),
                URLQueryItem(name: "maxNo", value: "50"),
                URLQueryItem(name: "r", value: "1500"),
                URLQueryItem(name: "type", value: "SE"),
                URLQueryItem(name: "format", value: "json")
            ]
        )
    }

    static func departureBoardURL(
        stopId: String,
        configuration: AppConfiguration
    ) throws -> URL {
        try url(
            path: "departureBoard",
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "lang", value: "fr"),
                URLQueryItem(name: "id", value: stopId),
                URLQueryItem(name: "format", value: "json")
            ]
        )
    }

    private static func url(
        path: String,
        configuration: AppConfiguration,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard configuration.hasATPAccessId, let accessId = configuration.atpAccessId else {
            throw ATPClientError.missingAccessId
        }

        let baseURL = configuration.apiBaseURL.appending(path: path)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ATPClientError.invalidResponse
        }

        components.queryItems = [URLQueryItem(name: "accessId", value: accessId)] + queryItems

        guard let url = components.url else {
            throw ATPClientError.invalidResponse
        }
        return url
    }
}
