import Foundation

/// Routing retains the passlist; the small departure-card model stays unchanged.
nonisolated struct ATPRoutingBoard: Sendable {
    var journeys: [ATPRoutingJourney]
}

nonisolated struct ATPRoutingJourney: Sendable {
    let departure: Departure
    var stops: [ATPRoutingStopPrediction] = []
}

nonisolated struct ATPRoutingStopPrediction: Sendable, Hashable {
    let stopID: String
    var routeIndex: Int? = nil
    var scheduledArrival: Date? = nil
    var scheduledDeparture: Date? = nil
    var predictedArrival: Date? = nil
    var predictedDeparture: Date? = nil
    var platform: String? = nil
    var boardingCancelled = false
    var alightingCancelled = false
}

extension ATPMapper {
    static func mapRoutingBoard(_ response: ATPDepartureBoardResponse, stopID: String) -> ATPRoutingBoard {
        ATPRoutingBoard(journeys: (response.departure ?? []).compactMap { dto in
            guard let departure = mapDepartures(
                ATPDepartureBoardResponse(departure: [dto]), stopId: stopID
            ).first else { return nil }
            let stops = (dto.stops?.stop ?? []).compactMap { stop -> ATPRoutingStopPrediction? in
                guard let id = stop.extId ?? stop.id else { return nil }
                return ATPRoutingStopPrediction(
                    stopID: id,
                    routeIndex: stop.routeIdx,
                    scheduledArrival: date(dateString: stop.arrDate, timeString: stop.arrTime),
                    scheduledDeparture: date(dateString: stop.depDate, timeString: stop.depTime),
                    predictedArrival: date(dateString: stop.rtArrDate ?? stop.arrDate, timeString: stop.rtArrTime),
                    predictedDeparture: date(dateString: stop.rtDepDate ?? stop.depDate, timeString: stop.rtDepTime),
                    platform: stop.rtDepTrack ?? stop.rtDepPlatform?.text ?? stop.depTrack ?? stop.depPlatform?.text,
                    boardingCancelled: stop.cancelled == true || stop.cancelledDeparture == true
                        || stop.rtBoarding == false || stop.boarding == false,
                    alightingCancelled: stop.cancelled == true || stop.cancelledArrival == true
                        || stop.rtAlighting == false || stop.alighting == false
                )
            }
            return ATPRoutingJourney(departure: departure, stops: stops)
        })
    }
}

nonisolated struct ATPPasslist: Decodable {
    let stop: [ATPWaystop]?
    enum CodingKeys: String, CodingKey { case stop = "Stop" }
}

nonisolated struct ATPWaystop: Decodable {
    let id: String?
    let extId: String?
    let routeIdx: Int?
    let arrDate: String?
    let arrTime: String?
    let depDate: String?
    let depTime: String?
    let rtArrDate: String?
    let rtArrTime: String?
    let rtDepDate: String?
    let rtDepTime: String?
    let depTrack: String?
    let rtDepTrack: String?
    let depPlatform: ATPPlatform?
    let rtDepPlatform: ATPPlatform?
    let cancelled: Bool?
    let cancelledDeparture: Bool?
    let cancelledArrival: Bool?
    let boarding: Bool?
    let alighting: Bool?
    let rtBoarding: Bool?
    let rtAlighting: Bool?
}
