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
        case cancelled
        case product = "Product"
    }
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
