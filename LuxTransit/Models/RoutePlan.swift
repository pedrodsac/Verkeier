import Foundation

nonisolated struct RoutePlan: Codable, Hashable, Identifiable, Sendable {
    nonisolated struct Leg: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let mode: TransportMode
        let instruction: String?
        let transportKind: RouteLegTransportKind
        let routeName: String?
        let routeId: String?
        let tripId: String?
        let originStopId: String?
        let destinationStopId: String?
        let origin: LocationPoint
        let destination: LocationPoint
        let departureTime: Date?
        let arrivalTime: Date?
        let scheduledDepartureTime: Date?
        let scheduledArrivalTime: Date?
        let realtimeDepartureTime: Date?
        let realtimeArrivalTime: Date?
        let distanceMeters: Double?
        let mapCoordinates: [RouteMapCoordinate]
        let roadRoutingHint: RouteLegRoadRoutingHint
        let platform: String?
        let delayMinutes: Int?
        let liveStatus: RouteLegLiveStatus
        let transferWarning: String?

        init(
            id: String,
            mode: TransportMode,
            instruction: String? = nil,
            transportKind: RouteLegTransportKind,
            routeName: String? = nil,
            routeId: String? = nil,
            tripId: String? = nil,
            originStopId: String? = nil,
            destinationStopId: String? = nil,
            origin: LocationPoint,
            destination: LocationPoint,
            departureTime: Date? = nil,
            arrivalTime: Date? = nil,
            scheduledDepartureTime: Date? = nil,
            scheduledArrivalTime: Date? = nil,
            realtimeDepartureTime: Date? = nil,
            realtimeArrivalTime: Date? = nil,
            distanceMeters: Double? = nil,
            mapCoordinates: [RouteMapCoordinate] = [],
            roadRoutingHint: RouteLegRoadRoutingHint = .none,
            platform: String? = nil,
            delayMinutes: Int? = nil,
            liveStatus: RouteLegLiveStatus = .scheduled,
            transferWarning: String? = nil
        ) {
            self.id = id
            self.mode = mode
            self.instruction = instruction
            self.transportKind = transportKind
            self.routeName = routeName
            self.routeId = routeId
            self.tripId = tripId
            self.originStopId = originStopId
            self.destinationStopId = destinationStopId
            self.origin = origin
            self.destination = destination
            self.departureTime = departureTime
            self.arrivalTime = arrivalTime
            self.scheduledDepartureTime = scheduledDepartureTime ?? departureTime
            self.scheduledArrivalTime = scheduledArrivalTime ?? arrivalTime
            self.realtimeDepartureTime = realtimeDepartureTime
            self.realtimeArrivalTime = realtimeArrivalTime
            self.distanceMeters = distanceMeters
            self.mapCoordinates = mapCoordinates
            self.roadRoutingHint = roadRoutingHint
            self.platform = platform
            self.delayMinutes = delayMinutes
            self.liveStatus = liveStatus
            self.transferWarning = transferWarning
        }
    }

    let id: String
    let origin: LocationPoint
    let destination: LocationPoint
    let expectedTravelTime: TimeInterval?
    let distanceMeters: Double?
    let legs: [Leg]
    let dataSource: DataSource
}

enum RouteLegTransportKind: String, Codable, Hashable, Sendable {
    case transit
    case walking
    case automobile
    case unknown

    var displayName: String {
        switch self {
        case .transit: "Transit"
        case .walking: "Walking"
        case .automobile: "Driving"
        case .unknown: "Route"
        }
    }
}

enum RouteLegRoadRoutingHint: String, Codable, Hashable, Sendable {
    case none
    case automobile
    case walking
}

enum RouteLegLiveStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case live
    case delayed
    case cancelled
    case unknown

    var displayText: String {
        switch self {
        case .scheduled: "Scheduled"
        case .live: "Live"
        case .delayed: "Delayed"
        case .cancelled: "Cancelled"
        case .unknown: "Status unknown"
        }
    }
}
