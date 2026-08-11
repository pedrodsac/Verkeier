import Foundation

struct ATPNearbyStopsResponse: Decodable {
    let stopLocationOrCoordLocation: [ATPStopLocationWrapper]
}

struct ATPStopLocationWrapper: Decodable {
    let stopLocation: ATPStopLocation?
    let coordLocation: ATPStopLocation?

    enum CodingKeys: String, CodingKey {
        case stopLocation = "StopLocation"
        case coordLocation = "CoordLocation"
    }
}

struct ATPStopLocation: Decodable {
    let id: String?
    let extId: String?
    let name: String?
    let lon: Double?
    let lat: Double?
    let productAtStop: [ATPProduct]?

    enum CodingKeys: String, CodingKey {
        case id
        case extId
        case name
        case lon
        case lat
        case productAtStop = "productAtStop"
    }
}

struct ATPDepartureBoardResponse: Decodable {
    let departure: [ATPDeparture]?

    enum CodingKeys: String, CodingKey {
        case departure = "Departure"
    }
}

struct ATPDeparture: Decodable {
    let name: String?
    let type: String?
    let stop: String?
    let stopid: String?
    let stopExtId: String?
    let time: String?
    let date: String?
    let rtTime: String?
    let rtDate: String?
    let direction: String?
    let platform: String?
    let rtPlatform: String?
    let track: String?
    let rtTrack: String?
    let cancelled: Bool?
    let product: ATPProduct?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case stop
        case stopid
        case stopExtId
        case time
        case date
        case rtTime
        case rtDate
        case direction
        case platform
        case rtPlatform
        case track
        case rtTrack
        case cancelled
        case product = "Product"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        stop = try container.decodeIfPresent(String.self, forKey: .stop)
        stopid = try container.decodeIfPresent(String.self, forKey: .stopid)
        stopExtId = try container.decodeIfPresent(String.self, forKey: .stopExtId)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        rtTime = try container.decodeIfPresent(String.self, forKey: .rtTime)
        rtDate = try container.decodeIfPresent(String.self, forKey: .rtDate)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled)
        platform = Self.decodePlatform(from: container, key: .platform)
        rtPlatform = Self.decodePlatform(from: container, key: .rtPlatform)
        track = Self.decodePlatform(from: container, key: .track)
        rtTrack = Self.decodePlatform(from: container, key: .rtTrack)
        product = Self.decodeProduct(from: container)
    }

    private static func decodePlatform(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let platform = try? container.decodeIfPresent(String.self, forKey: key) {
            return normalizedPlatform(platform)
        }
        if let platform = try? container.decodeIfPresent(ATPPlatform.self, forKey: key) {
            return normalizedPlatform(platform.text)
        }
        return nil
    }

    private static func normalizedPlatform(_ platform: String?) -> String? {
        guard let platform else { return nil }
        let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeProduct(from container: KeyedDecodingContainer<CodingKeys>) -> ATPProduct? {
        if let product = try? container.decodeIfPresent(ATPProduct.self, forKey: .product) {
            return product
        }
        if let products = try? container.decodeIfPresent([ATPProduct].self, forKey: .product) {
            return products.first
        }
        return nil
    }
}

struct ATPPlatform: Decodable {
    let text: String?
}

struct ATPProduct: Decodable {
    let name: String?
    let line: String?
    let catOut: String?
    let catOutL: String?
    let operatorName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case line
        case catOut
        case catOutL
        case operatorName = "operator"
    }
}
