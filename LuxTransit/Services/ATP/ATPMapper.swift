import Foundation

enum ATPMapper {
    static func mapNearbyStops(_ response: ATPNearbyStopsResponse) -> [Stop] {
        response.stopLocationOrCoordLocation.compactMap { wrapper in
            guard let dto = wrapper.stopLocation ?? wrapper.coordLocation else { return nil }
            guard let id = dto.extId ?? dto.id, let name = dto.name, let latitude = dto.lat, let longitude = dto.lon else {
                return nil
            }

            return Stop(
                id: id,
                name: cleanedStopName(name),
                locality: locality(from: name),
                location: LocationPoint(id: id, name: cleanedStopName(name), latitude: latitude, longitude: longitude),
                modes: modes(from: dto.productAtStop ?? []),
                dataSource: .atpOpenAPI
            )
        }
    }

    static func mapDepartures(_ response: ATPDepartureBoardResponse, stopId: String) -> [Departure] {
        (response.departure ?? []).enumerated().map { index, dto in
            let scheduled = date(dateString: dto.date, timeString: dto.time)
            let realtime = date(dateString: dto.rtDate ?? dto.date, timeString: dto.rtTime)
            let delayMinutes = delayMinutes(scheduled: scheduled, realtime: realtime)
            let lineName = dto.product?.line ?? dto.name ?? dto.product?.name ?? "?"

            return Departure(
                id: "\(stopId)-\(dto.name ?? lineName)-\(dto.date ?? "")-\(dto.time ?? "")-\(index)",
                stopId: dto.stopExtId ?? dto.stopid ?? stopId,
                routeId: dto.product?.line,
                lineName: lineName,
                destination: dto.direction ?? "",
                scheduledDeparture: scheduled,
                realtimeDeparture: realtime,
                delayMinutes: delayMinutes,
                platform: dto.platform,
                operatorName: dto.product?.operatorName,
                isCancelled: dto.cancelled ?? false,
                isStatusUnknown: scheduled == nil,
                dataSource: .atpOpenAPI,
                lastUpdated: .now
            )
        }
    }

    private static func modes(from products: [ATPProduct]) -> [TransportMode] {
        let mapped = products.map { product in
            mode(from: product.catOutL ?? product.catOut ?? product.name ?? product.line)
        }
        return Array(Set(mapped)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func mode(from rawValue: String?) -> TransportMode {
        let value = (rawValue ?? "").lowercased()
        if value.contains("train") || value.contains("ter") || value.contains("re") {
            return .train
        }
        if value.contains("tram") {
            return .tram
        }
        if value.contains("bus") || value.contains("rgtr") {
            return .bus
        }
        if value.contains("funicular") {
            return .funicular
        }
        return .unknown
    }

    private static func delayMinutes(scheduled: Date?, realtime: Date?) -> Int? {
        guard let scheduled, let realtime else { return nil }
        return max(0, Int((realtime.timeIntervalSince(scheduled) / 60).rounded()))
    }

    private static func date(dateString: String?, timeString: String?) -> Date? {
        guard let dateString, let timeString else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if let date = formatter.date(from: "\(dateString) \(timeString)") {
            return date
        }

        formatter.dateFormat = "yyyyMMdd HH:mm:ss"
        if let date = formatter.date(from: "\(dateString) \(timeString)") {
            return date
        }

        formatter.dateFormat = "yyyyMMdd HHmmss"
        if let date = formatter.date(from: "\(dateString) \(timeString)") {
            return date
        }

        formatter.dateFormat = "yyyyMMdd HH:mm"
        return formatter.date(from: "\(dateString) \(timeString)")
    }

    private static func cleanedStopName(_ name: String) -> String {
        name.components(separatedBy: ", ").last ?? name
    }

    private static func locality(from name: String) -> String? {
        let components = name.components(separatedBy: ", ")
        guard components.count > 1 else { return nil }
        return components.first
    }
}
