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
