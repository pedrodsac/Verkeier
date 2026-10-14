import CoreLocation
import MapKit
import Observation

/// Stop and place search, plus the stops the rider opened recently.
@MainActor @Observable
final class SearchModel {
    var searchQuery = ""
    var searchResults: [Stop] = []
    var recentStops: [Stop] = []

    func loadRecentStops(using store: RoutePlannerStore = .shared) {
        recentStops = store.recentStops()
    }

    func recordRecentStop(_ stop: Stop, using store: RoutePlannerStore = .shared) {
        recentStops = store.recordRecentStop(stop)
    }

    func searchStops(using gtfsService: any GTFSService) async {
        let query = searchQuery
        async let mapKitLookup = Self.mapKitStops(matching: query)
        async let gtfsLookup = gtfsService.searchStops(query: query)

        // A newer keystroke may have superseded this query while MapKit ran.
        guard query == searchQuery else { return }
        let staticStops = await gtfsLookup
        let mapStops = await mapKitLookup
        searchResults = (staticStops + mapStops).deduplicatedByExactName()
    }
}

// MARK: - MapKit places

extension SearchModel {
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
            coordinate.latitude != 0 || coordinate.longitude != 0
        else { return nil }

        return Stop(
            id: "mapkit:\(coordinate.latitude),\(coordinate.longitude)",
            name: item.name ?? "Place",
            location: LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            modes: [],
            dataSource: .mapKit
        )
    }
}
