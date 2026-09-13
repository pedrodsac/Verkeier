import Foundation
import MobiliteitKit

protocol LiveTransitService: Sendable {
    var isConfigured: Bool { get }
    func nearbyStops(to location: LocationPoint, radiusMeters: Int, limit: Int) async throws -> [LiveTransitStop]
    func departureBoard(for stop: Stop, filter: TransitBoardFilter) async throws -> [Departure]
}

extension LiveTransitService {
    func resolvedStop(for stop: Stop, gtfsService: any GTFSService) async -> Stop {
        guard stop.hafasStationIDs.isEmpty else { return stop }
        do {
            let candidates = try await nearbyStops(to: stop.location, radiusMeters: 100, limit: 12)
            let named = candidates.filter {
                $0.name.normalizedForSearch == stop.name.normalizedForSearch
                    && Self.distanceMeters(from: stop.location, to: $0.location) <= 75
            }
            guard named.count == 1,
                  let resolved = await gtfsService.matchLiveStop(named[0]),
                  resolved.gtfsStopID == stop.gtfsStopID else { return stop }
            return resolved
        } catch {
            return stop
        }
    }

    private static func distanceMeters(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitudeRadians = lhs.latitude * .pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitudeRadians) * cos(rhs.latitude * .pi / 180)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct LiveTransitStop: Sendable, Hashable {
    let stationID: String
    let externalID: String?
    let name: String
    let location: LocationPoint
    let distanceMeters: Int?
    let modes: [TransportMode]
}

enum LiveTransitError: LocalizedError, Equatable {
    case notConfigured
    case noLiveIdentifier
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Live departures are not configured."
        case .noLiveIdentifier: "This stop has no verified live departure-board identifier."
        case .invalidResponse: "The live transit service returned an invalid response."
        case let .httpStatus(status): "The live transit service returned HTTP \(status)."
        case let .decoding(reason): "The live transit response could not be read: \(reason)"
        }
    }
}

struct UnavailableLiveTransitService: LiveTransitService {
    let isConfigured = false

    func nearbyStops(to _: LocationPoint, radiusMeters _: Int, limit _: Int) async throws -> [LiveTransitStop] {
        throw LiveTransitError.notConfigured
    }

    func departureBoard(for _: Stop, filter _: TransitBoardFilter) async throws -> [Departure] {
        throw LiveTransitError.notConfigured
    }
}

/// App-facing mapping around MobiliteitKit's typed HAFAS client. Wire-format
/// decoding stays in MobiliteitKit so every client of the package gets the
/// same handling for ATP's response variants.
struct MobiliteitLiveTransitService: LiveTransitService {
    let proxyURL: URL?

    var isConfigured: Bool { proxyURL != nil }

    func nearbyStops(to location: LocationPoint, radiusMeters: Int, limit: Int) async throws -> [LiveTransitStop] {
        guard proxyURL != nil else { throw LiveTransitError.notConfigured }
        let stops = try await client.nearbyStops(
            HafasNearbyStopsRequest(
                coordinate: Coordinate(latitude: location.latitude, longitude: location.longitude),
                radiusMeters: radiusMeters,
                maximumResults: limit,
                language: language,
                locationType: "SE"
            )
        )

        return stops.compactMap { stop in
            guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
            return LiveTransitStop(
                stationID: stop.id,
                externalID: stop.externalID,
                name: stop.name,
                location: LocationPoint(
                    id: "hafas:\(stop.id)", name: stop.name,
                    latitude: latitude, longitude: longitude
                ),
                distanceMeters: stop.distanceMeters,
                modes: modes(productClass: stop.products)
            )
        }
    }

    func departureBoard(for stop: Stop, filter: TransitBoardFilter) async throws -> [Departure] {
        guard proxyURL != nil else { throw LiveTransitError.notConfigured }
        guard let stationID = stop.hafasStationIDs.first else {
            throw LiveTransitError.noLiveIdentifier
        }

        let board = try await client.departureBoard(
            HafasDepartureBoardRequest(
                stationID: stationID,
                language: language,
                directionStationID: filter.destinationStopID,
                durationMinutes: filter.durationMinutes,
                maximumJourneys: filter.maximumJourneys,
                products: filter.products,
                operators: filter.operators,
                platforms: filter.platforms,
                realtimeMode: filter.realtimeMode == .full ? .full : .off,
                includePasslist: true
            )
        )

        let updatedAt = Date.now
        return board.departures.values.compactMap { departure in
            map(departure, stop: stop, updatedAt: updatedAt)
        }
        .sorted {
            ($0.realtimeDeparture ?? $0.scheduledDeparture ?? .distantFuture)
                < ($1.realtimeDeparture ?? $1.scheduledDeparture ?? .distantFuture)
        }
    }

    private var client: MobiliteitAPIClient {
        guard let proxyURL else {
            return MobiliteitAPIClient(apiKey: "", baseURL: MobiliteitAPIClient.defaultBaseURL)
        }
        return MobiliteitAPIClient(apiKey: "", baseURL: proxyURL.appendingPathComponent("atp"))
    }

    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private func map(_ source: HafasDeparture, stop: Stop, updatedAt: Date) -> Departure? {
        let scheduled = Self.date(date: source.plannedDate, time: source.plannedTime)
        let realtime = Self.date(
            date: source.realtimeDate ?? source.plannedDate,
            time: source.realtimeTime
        )
        guard scheduled != nil || realtime != nil else { return nil }

        let product = source.product
        let lineName = product?.line ?? source.name ?? product?.name ?? product?.categoryShort ?? "Service"
        let trimmedDirection = source.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destination = trimmedDirection.isEmpty ? "Unknown destination" : trimmedDirection
        let delay = scheduled.flatMap { planned in
            realtime.map { Int(($0.timeIntervalSince(planned) / 60).rounded()) }
        }
        let notes = source.notes.values.compactMap { note in
            note.textLong ?? note.textNormal ?? note.textShort ?? note.value
        }
        let journeyID = source.journeyReference?.reference
        let generatedID = [stop.id, journeyID ?? "", lineName, destination, source.plannedDate ?? "", source.plannedTime ?? ""]
            .joined(separator: "|")

        return Departure(
            id: journeyID ?? generatedID,
            stopId: stop.id,
            routeId: product?.lineID,
            lineName: lineName,
            destination: destination,
            scheduledDeparture: scheduled,
            realtimeDeparture: realtime,
            delayMinutes: delay,
            platform: source.realtimePlatform?.text ?? source.platform?.text,
            operatorName: product?.operatorName,
            isCancelled: source.cancelled ?? false,
            isStatusUnknown: source.prognosisType?.uppercased() == "UNKNOWN",
            dataSource: .atpOpenAPI,
            lastUpdated: updatedAt,
            journeyReference: journeyID,
            serviceNote: notes.isEmpty ? nil : notes.joined(separator: " · ")
        )
    }

    private func modes(productClass: Int?) -> [TransportMode] {
        guard let productClass else { return [] }
        var result: [TransportMode] = []
        if productClass & HafasProductClass.bus.rawValue != 0 { result.append(.bus) }
        if productClass & HafasProductClass.tram.rawValue != 0 { result.append(.tram) }
        if productClass & (HafasProductClass.expressTrain.rawValue
            | HafasProductClass.nationalTrain.rawValue
            | HafasProductClass.localTrain.rawValue) != 0 {
            result.append(.train)
        }
        return result
    }

    private static func date(date: String?, time: String?) -> Date? {
        guard let date, let time else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let value = formatter.date(from: "\(date) \(time)") { return value }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }
}
