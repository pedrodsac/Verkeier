import Foundation

nonisolated enum WidgetDeparturesAPI {
    enum Error: Swift.Error {
        case missingConfiguration
        case invalidResponse
        case allPlatformRequestsFailed
    }

    static func stop(withID stopID: String?) -> SharedFavouriteStop? {
        let stops = SharedTransitDataStore.favouriteStops()
        guard let stopID else { return stops.first }
        return stops.first { $0.id == stopID }
    }

    static func fetchDepartures(for stop: SharedFavouriteStop) async throws -> [SharedWidgetDeparture] {
        let filter = stop.boardFilterData.flatMap { try? JSONDecoder().decode(BoardFilter.self, from: $0) }
        let platformIDs = normalizedPlatformIDs(stop.platformIds, fallback: stop.id)

        let boards = await withTaskGroup(of: [SharedWidgetDeparture]?.self) { group in
            for platformID in platformIDs {
                group.addTask {
                    try? await fetchDepartureBoard(stopID: platformID, filter: filter)
                }
            }

            var successfulBoards: [[SharedWidgetDeparture]] = []
            for await board in group {
                if let board { successfulBoards.append(board) }
            }
            return successfulBoards
        }

        guard !boards.isEmpty else { throw Error.allPlatformRequestsFailed }
        return mergedDepartures(boards.flatMap { $0 })
            .filter { !$0.destination.identifiesSameStation(as: stop.name) }
            .prefix(8)
            .map { $0 }
    }

    private static func fetchDepartureBoard(
        stopID: String,
        filter: BoardFilter?
    ) async throws -> [SharedWidgetDeparture] {
        let url = try departureBoardURL(stopID: stopID, filter: filter)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode else {
            throw Error.invalidResponse
        }

        let board = try JSONDecoder().decode(DepartureBoardResponse.self, from: data)
        return (board.departures ?? []).enumerated().compactMap { index, departure in
            if let currentIndex = departure.product?.routeIndexFrom,
               let finalIndex = departure.product?.routeIndexTo,
               currentIndex >= finalIndex {
                return nil
            }
            let scheduled = departureDate(date: departure.date, time: departure.time)
            let realtime = departureDate(
                date: departure.realtimeDate ?? departure.date,
                time: departure.realtimeTime
            )
            let lineName = departure.product?.line
                ?? departure.name
                ?? departure.product?.name
                ?? "?"
            let identifier = departure.journeyReference
                ?? "\(stopID)-\(lineName)-\(departure.date ?? "")-\(departure.time ?? "")-\(index)"

            return SharedWidgetDeparture(
                id: identifier,
                lineName: lineName,
                destination: departure.direction ?? "",
                scheduledDeparture: scheduled,
                realtimeDeparture: realtime,
                delayMinutes: delayMinutes(scheduled: scheduled, realtime: realtime),
                platform: departure.realtimeTrack
                    ?? departure.realtimePlatform
                    ?? departure.track
                    ?? departure.platform,
                isCancelled: departure.cancelled
                    ?? departure.journeyStatus?.lowercased().contains("cancel")
                    ?? false
            )
        }
    }

    private static func departureBoardURL(stopID: String, filter: BoardFilter?) throws -> URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "API_PROXY_URL") as? String,
              let baseURL = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme == "https" || baseURL.scheme == "http" else {
            throw Error.missingConfiguration
        }

        var components = URLComponents(
            url: baseURL.appending(path: "atp/departureBoard"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "lang", value: "fr"),
            URLQueryItem(name: "id", value: stopID),
            URLQueryItem(name: "direction", value: filter?.destinationStopID),
            URLQueryItem(name: "duration", value: String(filter?.durationMinutes ?? 120)),
            URLQueryItem(name: "maxJourneys", value: String(filter?.maximumJourneys ?? 20)),
            URLQueryItem(name: "products", value: filter?.products.map(String.init)),
            URLQueryItem(name: "operators", value: joined(filter?.operators)),
            URLQueryItem(name: "platforms", value: joined(filter?.platforms)),
            URLQueryItem(name: "rtMode", value: filter?.realtimeMode ?? "FULL"),
            URLQueryItem(name: "passlist", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ].filter { $0.value != nil }

        guard let url = components?.url else { throw Error.invalidResponse }
        return url
    }

    private static func joined(_ values: [String]?) -> String? {
        let values = values ?? []
        return values.isEmpty ? nil : values.joined(separator: ",")
    }

    private static func normalizedPlatformIDs(_ ids: [String], fallback: String) -> [String] {
        let cleaned = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [fallback] : Array(Set(cleaned)).sorted()
    }

    private static func mergedDepartures(
        _ departures: [SharedWidgetDeparture]
    ) -> [SharedWidgetDeparture] {
        var departuresByKey: [String: SharedWidgetDeparture] = [:]
        for departure in departures {
            let key = [
                departure.lineName,
                departure.destination,
                departure.scheduledDeparture?.timeIntervalSince1970.description ?? "",
                departure.platform ?? ""
            ].joined(separator: "|")
            let existing = departuresByKey[key]
            departuresByKey[key] = existing?.realtimeDeparture == nil
                && departure.realtimeDeparture != nil ? departure : existing ?? departure
        }
        return departuresByKey.values.sorted {
            ($0.displayDepartureDate ?? .distantFuture) < ($1.displayDepartureDate ?? .distantFuture)
        }
    }

    private static func delayMinutes(scheduled: Date?, realtime: Date?) -> Int? {
        guard let scheduled, let realtime else { return nil }
        return max(0, Int((realtime.timeIntervalSince(scheduled) / 60).rounded()))
    }

    private static func departureDate(date: String?, time: String?) -> Date? {
        guard let date, let time else { return nil }
        return dateFormatters.lazy.compactMap { $0.date(from: "\(date) \(time)") }.first
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyyMMdd HH:mm:ss", "yyyyMMdd HHmmss", "yyyyMMdd HH:mm"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
            formatter.dateFormat = $0
            return formatter
        }
    }()
}

private struct BoardFilter: Decodable {
    let products: Int?
    let operators: [String]
    let destinationStopID: String?
    let platforms: [String]
    let durationMinutes: Int
    let maximumJourneys: Int
    let realtimeMode: String

    private enum CodingKeys: String, CodingKey {
        case products
        case operators
        case destinationStopID
        case platforms
        case durationMinutes
        case maximumJourneys
        case realtimeMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decodeIfPresent(Int.self, forKey: .products)
        operators = try container.decodeIfPresent([String].self, forKey: .operators) ?? []
        destinationStopID = try container.decodeIfPresent(String.self, forKey: .destinationStopID)
        platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? []
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 120
        maximumJourneys = try container.decodeIfPresent(Int.self, forKey: .maximumJourneys) ?? 20
        realtimeMode = try container.decodeIfPresent(String.self, forKey: .realtimeMode) ?? "FULL"
    }
}

private struct DepartureBoardResponse: Decodable {
    let departures: [WidgetAPIDeparture]?

    private enum CodingKeys: String, CodingKey {
        case departures = "Departure"
    }
}

private struct WidgetAPIDeparture: Decodable {
    let name: String?
    let time: String?
    let date: String?
    let realtimeTime: String?
    let realtimeDate: String?
    let direction: String?
    let platform: String?
    let realtimePlatform: String?
    let track: String?
    let realtimeTrack: String?
    let cancelled: Bool?
    let product: Product?
    let journeyReference: String?
    let journeyStatus: String?

    private enum CodingKeys: String, CodingKey {
        case name, time, date, direction, platform, track, cancelled
        case realtimeTime = "rtTime"
        case realtimeDate = "rtDate"
        case realtimePlatform = "rtPlatform"
        case realtimeTrack = "rtTrack"
        case product = "Product"
        case journeyReference = "JourneyDetailRef"
        case journeyStatus = "JourneyStatus"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        realtimeTime = try container.decodeIfPresent(String.self, forKey: .realtimeTime)
        realtimeDate = try container.decodeIfPresent(String.self, forKey: .realtimeDate)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        platform = Self.platform(from: container, key: .platform)
        realtimePlatform = Self.platform(from: container, key: .realtimePlatform)
        track = Self.platform(from: container, key: .track)
        realtimeTrack = Self.platform(from: container, key: .realtimeTrack)
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled)
        product = (try? container.decodeIfPresent(Product.self, forKey: .product))
            ?? (try? container.decodeIfPresent([Product].self, forKey: .product))?.first
        journeyReference = (try? container.decodeIfPresent(JourneyReference.self, forKey: .journeyReference))?.value
            ?? (try? container.decodeIfPresent(String.self, forKey: .journeyReference))
        journeyStatus = (try? container.decodeIfPresent(String.self, forKey: .journeyStatus))
            ?? (try? container.decodeIfPresent(JourneyStatus.self, forKey: .journeyStatus))?.value
    }

    private static func platform(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        (try? container.decodeIfPresent(String.self, forKey: key))
            ?? (try? container.decodeIfPresent(Platform.self, forKey: key))?.text
    }

    struct Product: Decodable {
        let name: String?
        let line: String?
        let routeIndexFrom: Int?
        let routeIndexTo: Int?

        private enum CodingKeys: String, CodingKey {
            case name, line
            case routeIndexFrom = "routeIdxFrom"
            case routeIndexTo = "routeIdxTo"
        }
    }

    private struct Platform: Decodable { let text: String? }

    private struct JourneyReference: Decodable {
        let value: String?
        private enum CodingKeys: String, CodingKey { case value = "ref" }
    }

    private struct JourneyStatus: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decodeIfPresent(String.self, forKey: .status)
                ?? container.decodeIfPresent(String.self, forKey: .text)
        }

        private enum CodingKeys: String, CodingKey { case status, text }
    }
}
