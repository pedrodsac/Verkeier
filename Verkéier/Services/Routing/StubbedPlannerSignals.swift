import Foundation

// MARK: - Historical reliability

/// Historical on-time reliability for a route or connection.
///
/// No public Luxembourg feed exposes per-route historical punctuality yet, so
/// the bundled implementation returns `nil` and the UI shows nothing until a
/// feed is wired in.
// ponytail: stubbed — wire when a historical reliability feed is confirmed.
protocol RouteReliabilityService: Sendable {
    /// On-time probability (0...1) for a connection on a given weekday/time, or
    /// `nil` when unknown.
    func reliabilityScore(routeId: String, at date: Date) async -> Double?
}

struct UnavailableRouteReliabilityService: RouteReliabilityService {
    func reliabilityScore(routeId _: String, at _: Date) async -> Double? {
        nil
    }
}

// MARK: - Park + Ride

/// A Park-and-Ride site a driver can transfer to transit from.
struct ParkAndRideSite: Identifiable, Hashable {
    let id: String
    let name: String
    let location: LocationPoint
    let capacity: Int?
}

/// Park-and-Ride sites near a coordinate.
///
/// No P+R dataset is bundled yet, so the live implementation returns an empty
/// list; the map layer and trip suggestions stay hidden until one is wired in.
// ponytail: stubbed — wire when a Park+Ride location dataset is confirmed.
protocol ParkAndRideService: Sendable {
    func parkAndRideSites(near location: LocationPoint) async -> [ParkAndRideSite]
}

struct UnavailableParkAndRideService: ParkAndRideService {
    func parkAndRideSites(near _: LocationPoint) async -> [ParkAndRideSite] {
        []
    }
}

// MARK: - Live vehicle positions

/// A live vehicle position for drawing a moving train/tram/bus dot on the map.
struct VehiclePosition: Identifiable, Hashable {
    let id: String
    let routeId: String?
    let mode: TransportMode
    let location: LocationPoint
    let bearingDegrees: Double?
}

/// Live vehicle positions near a coordinate. ATP does not expose a
/// vehicle-position stream today, so the live implementation returns nothing.
// ponytail: stubbed — wire when an ATP vehicle-position stream is confirmed.
protocol VehiclePositionService: Sendable {
    func vehiclePositions(near location: LocationPoint) async -> [VehiclePosition]
}

struct UnavailableVehiclePositionService: VehiclePositionService {
    func vehiclePositions(near _: LocationPoint) async -> [VehiclePosition] {
        []
    }
}

// MARK: - Bike sharing

/// A vel’OH! station in Luxembourg City.
nonisolated struct BikeShareStation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let location: LocationPoint
    let bikesAvailable: Int?
    let docksAvailable: Int?
    let capacity: Int?
    let isOpen: Bool?
    let lastUpdated: Date?

    nonisolated var displayName: String {
        name.stationDisplayName
    }

    nonisolated init(
        id: String,
        name: String,
        location: LocationPoint,
        bikesAvailable: Int? = nil,
        docksAvailable: Int? = nil,
        capacity: Int? = nil,
        isOpen: Bool? = nil,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.name = name.stationDisplayName
        self.location = location
        self.bikesAvailable = bikesAvailable
        self.docksAvailable = docksAvailable
        self.capacity = capacity
        self.isOpen = isOpen
        self.lastUpdated = lastUpdated
    }
}

/// The latest station snapshot used by routing and route presentation.
nonisolated struct BikeShareSnapshot: Hashable, Codable, Sendable {
    let stations: [BikeShareStation]
    let fetchedAt: Date
}

/// Bike-share stations near a coordinate.
protocol BikeShareService: Sendable {
    func bikeShareStations(near location: LocationPoint) async -> [BikeShareStation]
    func refreshStaticStations() async
    func refreshAvailability() async
    func snapshot() async -> BikeShareSnapshot?
}

struct UnavailableBikeShareService: BikeShareService {
    func bikeShareStations(near _: LocationPoint) async -> [BikeShareStation] {
        []
    }

    func refreshStaticStations() async {}
    func refreshAvailability() async {}
    func snapshot() async -> BikeShareSnapshot? { nil }
}

// MARK: - Station facilities (amenities, elevator status, imagery)

/// Static and live facility info for a station: amenities, lift outages, imagery.
struct StationFacilities: Hashable {
    var hasTicketMachine: Bool?
    var hasWaitingRoom: Bool?
    var hasShelter: Bool?
    /// Names/labels of currently out-of-service elevators or escalators.
    var outOfServiceLifts: [String]
    /// Station photo / imagery, when an asset source provides one.
    var imageURL: URL?
}

/// Facilities for a stop. No amenity dataset, CFL lift-status infeed, or imagery
/// source is bundled yet, so the live implementation returns `nil`.
// ponytail: stubbed — wire when station amenity / CFL lift / imagery feeds are confirmed.
protocol StationFacilitiesService: Sendable {
    func facilities(forStopId stopId: String) async -> StationFacilities?
}

struct UnavailableStationFacilitiesService: StationFacilitiesService {
    func facilities(forStopId _: String) async -> StationFacilities? {
        nil
    }
}
