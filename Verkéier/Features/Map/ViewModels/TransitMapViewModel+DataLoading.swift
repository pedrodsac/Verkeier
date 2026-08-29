import CoreLocation
import Foundation
import MapKit

extension TransitMapViewModel {
    /// Runs an address/POI search bounded to Luxembourg and maps the hits to
    /// ``Stop`` values tagged ``DataSource/mapKit``.
    static func mapKitStops(matching query: String) async -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.8153, longitude: 6.1296),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap(mapKitStop)
    }

    static func mapKitStop(from item: MKMapItem) -> Stop? {
        let coordinate = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        return Stop(
            id: "mapkit:\(coordinate.latitude),\(coordinate.longitude)",
            name: item.name ?? "Place",
            location: LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            modes: [],
            dataSource: .mapKit
        )
    }

    static func areWithin(_ meters: CLLocationDistance, _ lhs: Stop, _ rhs: Stop) -> Bool {
        CLLocation(latitude: lhs.location.latitude, longitude: lhs.location.longitude)
            .distance(from: CLLocation(latitude: rhs.location.latitude, longitude: rhs.location.longitude)) < meters
    }

    func loadFavouriteDepartureBoards(
        using atpClient: any ATPClient,
        favourites: [Stop],
        filtersByStopID: [String: TransitBoardFilter] = [:]
    ) async -> [FavouriteDepartureBoardResult] {
        await withTaskGroup(of: FavouriteDepartureBoardResult.self) { group in
            var results: [FavouriteDepartureBoardResult] = []
            results.reserveCapacity(favourites.count)

            var iterator = favourites.enumerated().makeIterator()
            for _ in 0 ..< min(favouriteDepartureConcurrencyLimit, favourites.count) {
                guard let next = iterator.next() else { break }
                group.addTask {
                    await Self.loadFavouriteDepartureBoard(
                        using: atpClient,
                        stop: next.element,
                        filter: filtersByStopID[next.element.id] ?? TransitBoardFilter(),
                        index: next.offset
                    )
                }
            }

            while let result = await group.next() {
                results.append(result)
                if let next = iterator.next() {
                    group.addTask {
                        await Self.loadFavouriteDepartureBoard(
                        using: atpClient,
                        stop: next.element,
                        filter: filtersByStopID[next.element.id] ?? TransitBoardFilter(),
                            index: next.offset
                        )
                    }
                }
            }

            return results.sorted { $0.index < $1.index }
        }
    }

    static func loadFavouriteDepartureBoard(
        using atpClient: any ATPClient,
        stop: Stop,
        filter: TransitBoardFilter = TransitBoardFilter(),
        index: Int
    ) async -> FavouriteDepartureBoardResult {
        do {
            return try await FavouriteDepartureBoardResult(
                stopId: stop.id,
                departures: atpClient.departureBoards(
                    stopIds: stop.platformIds,
                    options: filter.options()
                ),
                didFail: false,
                index: index
            )
        } catch {
            return FavouriteDepartureBoardResult(
                stopId: stop.id,
                departures: [],
                didFail: true,
                index: index
            )
        }
    }
}
