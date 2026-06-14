import Foundation

protocol GTFSService: Sendable {
    func searchStops(query: String) -> [Stop]
    func stopsForMap(center: LocationPoint, latitudeDelta: Double, longitudeDelta: Double, limit: Int) -> [Stop]
    func stop(id: String) -> Stop?
    func routesForStop(id: String) -> [TransitRoute]
}
