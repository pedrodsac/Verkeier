import AsyncAlgorithms
import CoreLocation
import MapKit
import Observation

/// Stop and place search, plus the stops the rider opened recently.
@MainActor @Observable
final class SearchModel {
    var searchQuery = ""
    var searchResults: [Stop] = []
    var recentStops: [Stop] = []

    @ObservationIgnored private var typedQueries: AsyncStream<String>.Continuation?

    /// Recent stops with same-named platforms collapsed, for display.
    var distinctRecentStops: [Stop] {
        recentStops.deduplicatedByExactName()
    }

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

    /// Searches for the new query: at once when it was cleared, otherwise once
    /// typing pauses (see ``searchTypedQueries(using:)``).
    func queryDidChange(using gtfsService: any GTFSService) {
        guard !searchQuery.isEmpty else {
            Task { await searchStops(using: gtfsService) }
            return
        }
        typedQueries?.yield(searchQuery)
    }

    /// Runs the searches for typed queries, 250 ms after the last keystroke,
    /// for as long as the calling task lives.
    func searchTypedQueries(using gtfsService: any GTFSService) async {
        let (queries, continuation) = AsyncStream<String>.makeStream()
        typedQueries = continuation
        defer { typedQueries = nil }

        for await query in queries.debounce(for: .milliseconds(250)) {
            guard !Task.isCancelled else { return }
            guard query == searchQuery else { continue }
            await searchStops(using: gtfsService)
        }
    }

    /// The single stop a spoken or typed place name clearly refers to: the only
    /// exact name match, or the only result.
    func confidentMatch(for name: String) -> Stop? {
        let normalizedName = name.normalizedForSearch
        let exactMatches = searchResults.filter { $0.name.normalizedForSearch == normalizedName }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }
        return searchResults.count == 1 ? searchResults[0] : nil
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
