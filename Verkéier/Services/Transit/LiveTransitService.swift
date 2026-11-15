import Foundation
import MobiliteitKit

protocol LiveTransitService: Sendable {
    var isConfigured: Bool { get }
    func nearbyStops(to location: LocationPoint, radiusMeters: Int, limit: Int) async throws -> [LiveTransitStop]
    func departureBoard(for stop: Stop, filter: TransitBoardFilter) async throws -> [Departure]
    func departureBoardSnapshot(for stop: Stop, filter: TransitBoardFilter) async throws -> LiveDepartureBoardSnapshot
}

struct LiveDepartureBoardSnapshot: Sendable {
    let departures: [Departure]
    let fetchedAt: Date
}

extension LiveTransitService {
    func departureBoardSnapshot(for stop: Stop, filter: TransitBoardFilter) async throws -> LiveDepartureBoardSnapshot {
        let departures = try await departureBoard(for: stop, filter: filter)
        return .init(departures: departures, fetchedAt: departures.compactMap(\.lastUpdated).min() ?? .now)
    }

    func resolvedStop(for stop: Stop, gtfsService: any GTFSService) async -> Stop {
        // ATP accepts the numeric identifiers published by Luxembourg's GTFS
        // feed. Do not require a unique nearby-platform match for those stops.
        guard stop.hafasStationIDs.isEmpty, stop.gtfsStopID == nil else { return stop }
        do {
            let candidates = try await nearbyStops(to: stop.location, radiusMeters: 100, limit: 12)
            let named = candidates.filter {
                $0.name.normalizedForSearch == stop.name.normalizedForSearch
                    && Self.distanceMeters(from: stop.location, to: $0.location) <= 75
            }
            guard named.count == 1,
                let resolved = await gtfsService.matchLiveStop(named[0])
            else { return stop }
            return resolved
        } catch {
            return stop
        }
    }

    private static func distanceMeters(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitudeRadians = lhs.latitude * .pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let a =
            sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
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
    let session: URLSession
    let diagnostics: HTTPDiagnosticsObserver?

    init(proxyURL: URL?, session: URLSession = .shared, diagnostics: HTTPDiagnosticsObserver? = nil) {
        self.proxyURL = proxyURL
        self.session = session
        self.diagnostics = diagnostics
    }

    var isConfigured: Bool { proxyURL != nil }

    /// The same configured client is shared with realtime journey routing so
    /// departure boards and RAPTOR patches use one relay contract.
    var realtimeRoutingClient: MobiliteitAPIClient? {
        guard let proxyURL else { return nil }
        return MobiliteitAPIClient(
            apiKey: "",
            baseURL: proxyURL.appendingPathComponent("atp"),
            session: session,
            language: language,
            diagnostics: diagnostics
        )
    }

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
                    id: "hafas:\(stop.id)",
                    name: stop.name,
                    latitude: latitude,
                    longitude: longitude
                ),
                distanceMeters: stop.distanceMeters,
                modes: modes(productClass: stop.products)
            )
        }
    }

    func departureBoard(for stop: Stop, filter: TransitBoardFilter) async throws -> [Departure] {
        try await departureBoardSnapshot(for: stop, filter: filter).departures
    }

    func departureBoardSnapshot(for stop: Stop, filter: TransitBoardFilter) async throws -> LiveDepartureBoardSnapshot {
        guard proxyURL != nil else { throw LiveTransitError.notConfigured }
        guard let stationID = Self.stationIdentifier(for: stop) else {
            throw LiveTransitError.noLiveIdentifier
        }

        let snapshot = try await client.departureBoardSnapshot(
            HafasDepartureBoardRequest(
                stationID: stationID,
                language: language,
                directionStationID: filter.destinationStopID,
                // ATP supports at most 1,439 minutes; -1 returns every service in that window.
                durationMinutes: 1_439,
                maximumJourneys: -1,
                products: filter.products,
                operators: filter.operators,
                platforms: filter.platforms,
                realtimeMode: filter.realtimeMode == .full ? .serverDefault : .off,
                includePasslist: true,
                // Routing's cap: the board reads only the terminus, which ATP keeps, and the
                // same cap keeps this board in routing's cache scope so routing can reuse it.
                passlistMaximumStops: HafasRealtimeRoutingProvider.routingPasslistMaximumStops
            )
        )

        let departures = snapshot.board.departures.values.compactMap { departure in
            map(departure, stop: stop, updatedAt: snapshot.observedAt(for: departure))
        }
        .sorted {
            ($0.realtimeDeparture ?? $0.scheduledDeparture ?? .distantFuture)
                < ($1.realtimeDeparture ?? $1.scheduledDeparture ?? .distantFuture)
        }
        return .init(departures: departures, fetchedAt: snapshot.fetchedAt)
    }

    private var client: MobiliteitAPIClient {
        guard let realtimeRoutingClient else {
            return MobiliteitAPIClient(
                apiKey: "",
                baseURL: MobiliteitAPIClient.defaultBaseURL,
                session: session
            )
        }
        return realtimeRoutingClient
    }

    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    func map(_ source: HafasDeparture, stop: Stop, updatedAt: Date) -> Departure? {
        // Terminal arrivals have nowhere to travel from here, so omit them
        // from every consumer of the live board (including favourites and widgets).
        if Self.isTerminalArrival(source, at: stop) {
            return nil
        }

        let scheduled = HafasDepartureReading.scheduledDate(of: source)
        let realtime = HafasDepartureReading.realtimeDate(of: source)
        guard scheduled != nil || realtime != nil else { return nil }

        let product = source.product
        let lineName = HafasDepartureReading.lineName(of: source)
        let destination = HafasDepartureReading.destination(of: source)
        let delay = scheduled.flatMap { planned in
            realtime.map { Int(($0.timeIntervalSince(planned) / 60).rounded()) }
        }
        let notes = source.notes.values.compactMap { note in
            note.textLong ?? note.textNormal ?? note.textShort ?? note.value
        }
        let journeyID = source.journeyReference?.reference
        let generatedID = [
            stop.id, journeyID ?? "", lineName, destination, source.plannedDate ?? "", source.plannedTime ?? "",
        ]
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
            platform: HafasDepartureReading.platform(of: source),
            operatorName: product?.operatorName,
            isCancelled: source.cancelled ?? false,
            isStatusUnknown: source.prognosisType?.uppercased() == "UNKNOWN",
            dataSource: .atpOpenAPI,
            lastUpdated: updatedAt,
            journeyReference: journeyID,
            serviceNote: notes.isEmpty ? nil : notes.joined(separator: " · "),
            mode: modes(productClass: product?.productClass).first
        )
    }

    private func modes(productClass: Int?) -> [TransportMode] {
        guard let productClass else { return [] }
        var result: [TransportMode] = []
        if productClass & HafasProductClass.bus.rawValue != 0 { result.append(.bus) }
        if productClass & HafasProductClass.tram.rawValue != 0 { result.append(.tram) }
        if productClass
            & (HafasProductClass.expressTrain.rawValue
                | HafasProductClass.nationalTrain.rawValue
                | HafasProductClass.localTrain.rawValue) != 0
        {
            result.append(.train)
        }
        return result
    }

    static func stationIdentifier(for stop: Stop) -> String? {
        stop.liveStationID
    }

    static func isTerminalArrival(_ departure: HafasDeparture, at stop: Stop) -> Bool {
        HafasDepartureReading.isTerminalArrival(
            departure,
            stopIdentifiers: [stop.id, stop.gtfsStopID].compactMap { $0 } + stop.hafasStationIDs,
            stopName: stop.name
        )
    }
}
