import Foundation

nonisolated enum ATPMapper {
    static func mapNearbyStops(_ response: ATPNearbyStopsResponse) -> [Stop] {
        let platformStops: [ATPPlatformStop] = response.stopLocationOrCoordLocation.compactMap { wrapper in
            guard let dto = wrapper.stopLocation ?? wrapper.coordLocation else { return nil }
            guard let id = dto.extId ?? dto.id, let name = dto.name, let latitude = dto.lat, let longitude = dto.lon else {
                return nil
            }

            let locality = locality(from: name)
            let stationName = stationName(from: cleanedStopName(name))

            return ATPPlatformStop(
                id: id,
                name: stationName,
                locality: locality,
                latitude: latitude,
                longitude: longitude,
                modes: modes(from: dto.productAtStop ?? []),
                groupingKey: groupingKey(locality: locality, name: stationName)
            )
        }

        var groups: [String: [ATPPlatformStop]] = [:]
        var orderedKeys: [String] = []

        for platformStop in platformStops {
            if groups[platformStop.groupingKey] == nil {
                orderedKeys.append(platformStop.groupingKey)
            }
            groups[platformStop.groupingKey, default: []].append(platformStop)
        }

        return orderedKeys.compactMap { key in
            groups[key].map(groupedStop)
        }
    }

    static func mapDepartures(_ response: ATPDepartureBoardResponse, stopId: String) -> [Departure] {
        let dtos = response.departure ?? []
        let inferredPlatforms = inferredPlatforms(for: dtos, fallbackStopId: stopId)

        return dtos.enumerated().compactMap { index, dto in
            if let currentIndex = dto.product?.routeIndexFrom,
               let finalIndex = dto.product?.routeIndexTo,
               currentIndex >= finalIndex {
                return nil
            }
            let scheduled = date(dateString: dto.date, timeString: dto.time)
            let realtime = date(dateString: dto.rtDate ?? dto.date, timeString: dto.rtTime)
            let delayMinutes = delayMinutes(scheduled: scheduled, realtime: realtime)
            let lineName = dto.product?.line ?? dto.name ?? dto.product?.name ?? "?"
            let departureStopId = departureStopIdentifier(dto, fallback: stopId)
            let platformResolution = platformResolution(for: dto)
            let platform = platformResolution.effective
                ?? inferredPlatforms[departureStopId]

            return Departure(
                id: dto.journeyDetailReference ?? "\(stopId)-\(dto.name ?? lineName)-\(dto.date ?? "")-\(dto.time ?? "")-\(index)",
                stopId: departureStopId,
                routeId: dto.product?.line,
                lineName: lineName,
                destination: dto.direction ?? "",
                scheduledDeparture: scheduled,
                realtimeDeparture: realtime,
                delayMinutes: delayMinutes,
                platform: platform,
                operatorName: dto.product?.operatorName ?? dto.product?.operatorCode,
                isCancelled: dto.cancelled ?? dto.journeyStatus?.lowercased().contains("cancel") ?? false,
                isStatusUnknown: scheduled == nil,
                dataSource: .atpOpenAPI,
                lastUpdated: .now,
                previousPlatform: platformResolution.previous,
                journeyReference: dto.journeyDetailReference,
                serviceNote: dto.notes.isEmpty ? nil : dto.notes.joined(separator: " • ")
            )
        }
    }

    private static func platformResolution(for departure: ATPDeparture) -> PlatformResolution {
        // ATP's realtime track is the freshest explicit assignment. The
        // structured platform fields remain useful fallbacks for responses
        // where the scalar track fields are absent.
        let realtime = departure.rtTrack ?? departure.rtPlatform
        let scheduled = departure.track ?? departure.platform
        let effective = realtime ?? scheduled
        let previous = realtime != nil && scheduled != nil && realtime != scheduled
            ? scheduled
            : nil
        return PlatformResolution(effective: effective, previous: previous)
    }

    /// ATP can omit platform data on later departures while still identifying
    /// the physical stop. Infer it only when every explicit assignment for
    /// that physical stop agrees, avoiding guesses at stations where platforms
    /// legitimately vary by departure.
    private static func inferredPlatforms(
        for departures: [ATPDeparture],
        fallbackStopId: String
    ) -> [String: String] {
        var candidatesByStopID: [String: Set<String>] = [:]

        for departure in departures {
            guard let platform = platformResolution(for: departure).effective else { continue }
            let stopID = departureStopIdentifier(departure, fallback: fallbackStopId)
            candidatesByStopID[stopID, default: []].insert(platform)
        }

        return candidatesByStopID.compactMapValues { candidates in
            candidates.count == 1 ? candidates.first : nil
        }
    }

    private struct PlatformResolution {
        let effective: String?
        let previous: String?
    }

    private static func departureStopIdentifier(_ departure: ATPDeparture, fallback: String) -> String {
        departure.stopExtId ?? departure.stopid ?? fallback
    }

    static func mergedDepartures(_ departures: [Departure]) -> [Departure] {
        var keyedDepartures: [String: Departure] = [:]

        for departure in departures {
            keyedDepartures[dedupeKey(for: departure), default: departure] = preferred(
                keyedDepartures[dedupeKey(for: departure)],
                departure
            )
        }

        return keyedDepartures.values.sorted { lhs, rhs in
            let lhsDate = lhs.realtimeDeparture ?? lhs.scheduledDeparture ?? .distantFuture
            let rhsDate = rhs.realtimeDeparture ?? rhs.scheduledDeparture ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.lineName.localizedStandardCompare(rhs.lineName) == .orderedAscending
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

    static func date(dateString: String?, timeString: String?) -> Date? {
        guard let dateString, let timeString else { return nil }
        let combined = "\(dateString) \(timeString)"
        return dateFormatters.lazy.compactMap { $0.date(from: combined) }.first
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyyMMdd HH:mm:ss", "yyyyMMdd HHmmss", "yyyyMMdd HH:mm"]
        return formats.map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Luxembourg")
            f.dateFormat = format
            return f
        }
    }()

    private static func groupedStop(_ platformStops: [ATPPlatformStop]) -> Stop {
        let sortedPlatformIds = platformStops.map(\.id).sorted()
        let id = sortedPlatformIds.first ?? platformStops[0].id
        let name = platformStops[0].name
        let locality = platformStops[0].locality
        let latitude = platformStops.map(\.latitude).reduce(0, +) / Double(platformStops.count)
        let longitude = platformStops.map(\.longitude).reduce(0, +) / Double(platformStops.count)
        let modes = Array(Set(platformStops.flatMap(\.modes))).sorted { $0.rawValue < $1.rawValue }

        return Stop(
            id: id,
            name: name,
            locality: locality,
            location: LocationPoint(id: id, name: name, latitude: latitude, longitude: longitude),
            modes: modes,
            dataSource: .atpOpenAPI,
            platformIds: sortedPlatformIds
        )
    }

    private static func cleanedStopName(_ name: String) -> String {
        name.components(separatedBy: ", ").last ?? name
    }

    private static func stationName(from cleanedName: String) -> String {
        let patterns = [
            #"(?i)\s*\([^)]*\b(quai|platform|voie|gleis|track|bussteig)\b[^)]*\)\s*$"#,
            #"(?i)\s*[-–—]?\s*\b(quai|platform|voie|gleis|track|bussteig)\b\s*[A-Za-z0-9]+[A-Za-z]?\s*$"#,
            #"(?i)\s*[-–—]?\s*\b(platform|voie|gleis|track)\b\s*$"#
        ]

        let stripped = patterns.reduce(cleanedName) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? cleanedName : stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func locality(from name: String) -> String? {
        let components = name.components(separatedBy: ", ")
        guard components.count > 1 else { return nil }
        return components.first
    }

    private static func groupingKey(locality: String?, name: String) -> String {
        [locality, name]
            .compactMap { $0?.normalizedForATPGrouping }
            .joined(separator: "|")
    }

    private static func dedupeKey(for departure: Departure) -> String {
        [
            departure.routeId ?? departure.lineName,
            departure.destination,
            departure.scheduledDeparture?.timeIntervalSince1970.description ?? "",
            departure.platform ?? ""
        ]
        .joined(separator: "|")
    }

    private static func preferred(_ existing: Departure?, _ candidate: Departure) -> Departure {
        guard let existing else { return candidate }
        if existing.realtimeDeparture == nil, candidate.realtimeDeparture != nil {
            return candidate
        }
        return existing
    }
}

private struct ATPPlatformStop {
    let id: String
    let name: String
    let locality: String?
    let latitude: Double
    let longitude: Double
    let modes: [TransportMode]
    let groupingKey: String
}

private extension String {
    nonisolated var normalizedForATPGrouping: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
