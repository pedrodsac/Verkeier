import Foundation

protocol GTFSService: Sendable {
    nonisolated func searchStops(query: String) async -> [Stop]
    nonisolated func stopsForMap(center: LocationPoint, latitudeDelta: Double, longitudeDelta: Double, limit: Int) async -> [Stop]
    nonisolated func stop(id: String) async -> Stop?
    nonisolated func allStops() async -> [Stop]
    nonisolated func routesForStop(id: String) async -> [TransitRoute]
    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload?
}
