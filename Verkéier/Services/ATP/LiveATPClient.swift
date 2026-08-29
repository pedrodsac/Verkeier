import Foundation

final class LiveATPClient: ATPClient {
    private let configuration: AppConfiguration
    private let session: URLSession
    private let makeDecoder: @Sendable () -> JSONDecoder

    init(
        configuration: AppConfiguration = .current,
        session: URLSession = .shared,
        makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) {
        self.configuration = configuration
        self.session = session
        self.makeDecoder = makeDecoder
    }

    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        try await nearbyStops(
            latitude: latitude,
            longitude: longitude,
            options: ATPNearbyStopsOptions()
        )
    }

    nonisolated func nearbyStops(
        latitude: Double,
        longitude: Double,
        options: ATPNearbyStopsOptions
    ) async throws -> [Stop] {
        let request = try URLRequest(url: ATPRequestBuilder.nearbyStopsURL(
            latitude: latitude,
            longitude: longitude,
            options: options,
            configuration: configuration
        ))
        let response: ATPNearbyStopsResponse = try await fetch(request)
        return ATPMapper.mapNearbyStops(response)
    }

    nonisolated func departureBoard(stopId: String) async throws -> [Departure] {
        try await departureBoard(stopId: stopId, options: ATPDepartureBoardOptions())
    }

    nonisolated func departureBoard(
        stopId: String,
        options: ATPDepartureBoardOptions
    ) async throws -> [Departure] {
        let request = try URLRequest(url: ATPRequestBuilder.departureBoardURL(
            stopId: stopId,
            options: options,
            configuration: configuration
        ))
        let response: ATPDepartureBoardResponse = try await fetch(request)
        return ATPMapper.mapDepartures(response, stopId: stopId)
    }

    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure] {
        try await departureBoards(stopIds: stopIds, options: ATPDepartureBoardOptions())
    }

    nonisolated func departureBoards(
        stopIds: [String],
        options: ATPDepartureBoardOptions
    ) async throws -> [Departure] {
        let ids = ATPStopIdentifier.normalized(stopIds)
        guard !ids.isEmpty else { return [] }

        var departures: [Departure] = []
        var failureCount = 0
        var firstError: Error?

        await withTaskGroup(of: Result<[Departure], Error>.self) { group in
            for stopId in ids {
                group.addTask {
                    do {
                        return .success(try await self.departureBoard(stopId: stopId, options: options))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let board):
                    departures.append(contentsOf: board)
                case .failure(let error):
                    failureCount += 1
                    firstError = firstError ?? error
                }
            }
        }

        guard failureCount < ids.count else {
            throw firstError ?? ATPClientError.allPlatformRequestsFailed
        }

        return ATPMapper.mergedDepartures(departures)
    }

    private nonisolated func fetch<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATPClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ATPClientError.httpStatus(httpResponse.statusCode)
        }
        return try makeDecoder().decode(Response.self, from: data)
    }
}

enum ATPRequestBuilder {
    nonisolated static func nearbyStopsURL(
        latitude: Double,
        longitude: Double,
        options: ATPNearbyStopsOptions = ATPNearbyStopsOptions(),
        configuration: AppConfiguration
    ) throws -> URL {
        let options = options.normalized
        try url(
            path: "location.nearbystops",
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "originCoordLat", value: String(latitude)),
                URLQueryItem(name: "originCoordLong", value: String(longitude)),
                URLQueryItem(name: "maxNo", value: String(options.maximumResults)),
                URLQueryItem(name: "r", value: String(options.radiusMeters)),
                URLQueryItem(name: "type", value: "SE"),
                URLQueryItem(name: "products", value: options.products.map { String($0.rawValue) }),
                URLQueryItem(name: "lang", value: options.language),
                URLQueryItem(name: "format", value: "json")
            ].filter { $0.value != nil }
        )
    }

    nonisolated static func departureBoardURL(
        stopId: String,
        options: ATPDepartureBoardOptions = ATPDepartureBoardOptions(),
        configuration: AppConfiguration
    ) throws -> URL {
        let options = options.normalized
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        timeFormatter.dateFormat = "HH:mm"
        try url(
            path: "departureBoard",
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "lang", value: options.language),
                URLQueryItem(name: "id", value: stopId),
                URLQueryItem(name: "direction", value: options.directionStopID),
                URLQueryItem(name: "date", value: options.date.map(dateFormatter.string)),
                URLQueryItem(name: "time", value: options.date.map(timeFormatter.string)),
                URLQueryItem(name: "duration", value: String(options.durationMinutes)),
                URLQueryItem(name: "maxJourneys", value: String(options.maximumJourneys)),
                URLQueryItem(name: "products", value: options.products.map { String($0.rawValue) }),
                URLQueryItem(name: "operators", value: options.operators.isEmpty ? nil : options.operators.joined(separator: ",")),
                URLQueryItem(name: "lines", value: options.lines.isEmpty ? nil : options.lines.joined(separator: ",")),
                URLQueryItem(name: "platforms", value: options.platforms.isEmpty ? nil : options.platforms.joined(separator: ",")),
                URLQueryItem(name: "rtMode", value: options.realtimeMode.rawValue),
                URLQueryItem(name: "passlist", value: options.includePasslist ? "1" : "0"),
                URLQueryItem(name: "format", value: "json")
            ].filter { $0.value != nil }
        )
    }

    private nonisolated static func url(
        path: String,
        configuration: AppConfiguration,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        let baseURL: URL
        var requestQueryItems = queryItems

        if configuration.hasAPIProxyURL, let apiProxyURL = configuration.apiProxyURL {
            baseURL = apiProxyURL.appending(path: "atp/\(path)")
        } else if configuration.hasATPAccessId, let accessId = configuration.atpAccessId {
            baseURL = configuration.apiBaseURL.appending(path: path)
            requestQueryItems.insert(URLQueryItem(name: "accessId", value: accessId), at: 0)
        } else {
            throw ATPClientError.missingAccessId
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ATPClientError.invalidResponse
        }

        components.queryItems = requestQueryItems

        guard let url = components.url else {
            throw ATPClientError.invalidResponse
        }
        return url
    }
}
