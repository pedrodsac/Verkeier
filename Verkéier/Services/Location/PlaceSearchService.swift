import Foundation
import MapKit

/// Searches for addresses and map locations (not GTFS stops) so a rider can
/// plan a trip to/from any place, and the map search can jump to a location.
protocol PlaceSearchService: Sendable {
    /// Address, POI, and physical-location matches for `query`, biased toward
    /// `region` when provided.
    /// Returns an empty array for short or unmatched queries.
    func searchPlaces(query: String, near region: LocationPoint?) async -> [RoutePlace]
}

/// `MKLocalSearch`-backed implementation, biased to the Luxembourg area.
struct LivePlaceSearchService: PlaceSearchService {
    /// Roughly the centre of Luxembourg City; the search region spans the country.
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 49.611, longitude: 6.131)

    func searchPlaces(query: String, near region: LocationPoint?) async -> [RoutePlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest, .physicalFeature]
        request.region = MKCoordinateRegion(
            center: region?.coordinate ?? Self.defaultCenter,
            latitudinalMeters: 60000,
            longitudinalMeters: 60000
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        return response.mapItems.prefix(8).map { item in
            let coordinate = item.location.coordinate
            let name = item.name ?? trimmed
            return RoutePlace(
                title: name,
                subtitle: item.address?.shortAddress,
                location: LocationPoint(
                    name: name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                source: .search
            )
        }
    }
}

/// No-op for previews and tests — `MKLocalSearch` needs the network and a device.
struct EmptyPlaceSearchService: PlaceSearchService {
    func searchPlaces(query _: String, near _: LocationPoint?) async -> [RoutePlace] {
        []
    }
}
