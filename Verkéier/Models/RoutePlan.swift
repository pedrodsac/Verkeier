import Foundation

/// A computed door-to-door journey from one place to another.
///
/// A plan is an ordered list of ``RoutePlan/Leg`` values that alternate between
/// walking and transit. It is produced by a ``RouteService`` and usually wrapped
/// in a ``RouteOption`` (which adds map overlay and live-status derivations).
nonisolated struct RoutePlan: Codable, Hashable, Identifiable, Sendable {
    /// A single contiguous segment of a ``RoutePlan`` in one mode.
    ///
    /// Carries both scheduled and realtime times where known; the scheduled
    /// fields fall back to ``departureTime`` / ``arrivalTime`` when not given
    /// explicitly.
    nonisolated struct Leg: Codable, Hashable, Identifiable, Sendable {
        /// Stable identifier for the leg.
        let id: String
        /// Transport mode for this leg.
        let mode: TransportMode
        /// Optional turn-by-turn or ride instruction.
        let instruction: String?
        /// Coarse classification used for styling and routing hints.
        let transportKind: RouteLegTransportKind
        /// Public line label for transit legs.
        let routeName: String?
        /// Line terminus / direction (GTFS trip headsign) for transit legs.
        let headsign: String?
        /// Route identifier for transit legs.
        let routeId: String?
        /// Trip identifier for transit legs.
        let tripId: String?
        /// Origin stop identifier for transit legs.
        let originStopId: String?
        /// Destination stop identifier for transit legs.
        let destinationStopId: String?
        /// Number of stops traveled on a transit leg, including the alighting stop.
        let stopCount: Int?
        /// Where the leg starts.
        let origin: LocationPoint
        /// Where the leg ends.
        let destination: LocationPoint
        /// Effective departure time (realtime if available, else scheduled).
        let departureTime: Date?
        /// Effective arrival time (realtime if available, else scheduled).
        let arrivalTime: Date?
        /// Timetabled departure time.
        let scheduledDepartureTime: Date?
        /// Timetabled arrival time.
        let scheduledArrivalTime: Date?
        /// Realtime predicted departure, when a live feed provided one.
        let realtimeDepartureTime: Date?
        /// Realtime predicted arrival, when a live feed provided one.
        let realtimeArrivalTime: Date?
        /// Leg length in metres, for walking and driving legs.
        let distanceMeters: Double?
        /// Polyline coordinates used to draw the leg on the map.
        let mapCoordinates: [RouteMapCoordinate]
        /// Hint for how the leg's geometry should be road-snapped.
        let roadRoutingHint: RouteLegRoadRoutingHint
        /// Boarding platform for transit legs, when published.
        let platform: String?
        /// Delay in minutes for transit legs, when known.
        let delayMinutes: Int?
        /// Live-status classification for transit legs.
        let liveStatus: RouteLegLiveStatus
        /// Non-`nil` when the transfer onto this leg is tight or at risk.
        var transferWarning: String?
        /// Pickup/return station and availability details for a bike-share leg.
        let bikeShareDetails: BikeShareLegDetails?
        var departureTimingSource: RouteTimingSource? = nil
        var arrivalTimingSource: RouteTimingSource? = nil
        /// Additional allowance required after the preceding transfer walk.
        var requiredTransferSeconds: Int? = nil
        /// Whether walking time came from an actual pedestrian route or an estimate.
        var walkingEvidence: RouteWalkingEvidence? = nil

        init(
            id: String,
            mode: TransportMode,
            instruction: String? = nil,
            transportKind: RouteLegTransportKind,
            routeName: String? = nil,
            headsign: String? = nil,
            routeId: String? = nil,
            tripId: String? = nil,
            originStopId: String? = nil,
            destinationStopId: String? = nil,
            stopCount: Int? = nil,
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
            transferWarning: String? = nil,
            bikeShareDetails: BikeShareLegDetails? = nil
        ) {
            self.id = id
            self.mode = mode
            self.instruction = instruction
            self.transportKind = transportKind
            self.routeName = routeName
            self.headsign = headsign
            self.routeId = routeId
            self.tripId = tripId
            self.originStopId = originStopId
            self.destinationStopId = destinationStopId
            self.stopCount = stopCount
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
            self.bikeShareDetails = bikeShareDetails
        }
    }

    /// Stable identifier for the plan.
    let id: String
    /// Journey origin.
    let origin: LocationPoint
    /// Journey destination.
    let destination: LocationPoint
    /// Total expected travel time, if known.
    let expectedTravelTime: TimeInterval?
    /// Total distance in metres, if known.
    let distanceMeters: Double?
    /// Ordered legs that make up the journey.
    let legs: [Leg]
    /// Which feed/engine produced the plan.
    let dataSource: DataSource
}

/// The stations and live counts associated with one bike-share rental.
nonisolated struct BikeShareLegDetails: Codable, Hashable, Sendable {
    let pickupStation: BikeShareStation
    let returnStation: BikeShareStation
    let isAvailabilityWarning: Bool
}

/// Coarse classification of a ``RoutePlan/Leg``.
enum RouteLegTransportKind: String, Codable, Hashable, Sendable {
    /// A ride on a transit line.
    case transit
    /// An on-foot segment.
    case walking
    /// A driving segment (Apple Maps fallback).
    case automobile
    /// A vel’OH! bike-share ride.
    case bikeShare
    case unknown

    /// Human-readable name for the kind.
    var displayName: String {
        switch self {
        case .transit: "Transit"
        case .walking: "Walking"
        case .automobile: "Driving"
        case .bikeShare: "Bike share"
        case .unknown: "Route"
        }
    }
}

/// Hint for whether a leg's geometry should be snapped to a road/path network
/// when drawn, and by which profile.
enum RouteLegRoadRoutingHint: String, Codable, Hashable, Sendable {
    /// Use the straight geometry as given.
    case none
    case automobile
    case walking
    /// MapKit walking geometry used as a bicycle-path approximation.
    case bicycle
}

enum RouteWalkingEvidence: String, Codable, Hashable, Sendable {
    case routedPedestrian
    case estimate
}

/// Live-status classification for a transit ``RoutePlan/Leg``.
enum RouteLegLiveStatus: String, Codable, Hashable, Sendable {
    /// No realtime data; timetable only.
    case scheduled
    /// Realtime data present and on schedule.
    case live
    /// Realtime data present and running late.
    case delayed
    /// The trip has been cancelled.
    case cancelled
    case unknown

    /// Short label suitable for display.
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

/// Explicit predictions and extrapolations must remain distinguishable to riders.
nonisolated enum RouteTimingSource: String, Codable, Hashable, Sendable {
    case scheduled, observed, estimated
}
