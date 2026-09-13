import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func requestLocation(using locationService: LocationService) {
        locationService.requestWhenInUseAuthorization()
    }

    func loadNearbyStops(
        location: CLLocation?,
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService,
        force: Bool = false
    ) async {
        let requestLocation = location ?? CLLocation(
            latitude: defaultRegion.center.latitude,
            longitude: defaultRegion.center.longitude
        )
        guard force || shouldRefreshNearbyStops(for: requestLocation) else { return }
        lastNearbyStopsRequestLocation = requestLocation
        isLoadingNearbyStops = true
        nearbyStops = []
        nearbyStopsErrorMessage = nil

        let point = LocationPoint(
            name: "Current location",
            latitude: requestLocation.coordinate.latitude,
            longitude: requestLocation.coordinate.longitude
        )
        if liveTransitService.isConfigured {
            do {
                let liveStops = try await liveTransitService.nearbyStops(
                    to: point,
                    radiusMeters: 1_500,
                    limit: 50
                )
                nearbyStops = await liveStops.asyncMap { liveStop in
                    await gtfsService.matchLiveStop(liveStop) ?? Stop(
                        id: "hafas:\(liveStop.stationID)",
                        name: liveStop.name,
                        location: liveStop.location,
                        modes: liveStop.modes,
                        dataSource: .atpOpenAPI,
                        hafasStationIDs: [liveStop.stationID]
                    )
                }
            } catch {
                nearbyStops = await gtfsService.nearbyStops(to: point, radiusMeters: 1_500, limit: 50)
                nearbyStopsErrorMessage = nearbyStops.isEmpty
                    ? "Nearby stops could not be loaded."
                    : "Live nearby stops are unavailable; showing the timetable feed."
            }
        } else {
            nearbyStops = await gtfsService.nearbyStops(to: point, radiusMeters: 1_500, limit: 50)
            if nearbyStops.isEmpty {
                nearbyStopsErrorMessage = "The timetable is still being prepared."
            }
        }
        isLoadingNearbyStops = false
    }

    func shouldRefreshNearbyStops(for location: CLLocation) -> Bool {
        guard let lastNearbyStopsRequestLocation else { return true }
        return location.distance(from: lastNearbyStopsRequestLocation) >= nearbyStopsRefreshDistance
    }

    /// Loads the lines serving each nearby stop, with bounded concurrency, so
    /// the nearby list can show "12 · 14 · 25" rather than just a mode label.
    func loadNearbyStopRoutes(using gtfsService: any GTFSService) async {
        var routes: [String: [TransitRoute]] = [:]
        for stop in nearbyStops {
            routes[stop.id] = await gtfsService.routes(for: stop)
        }
        nearbyStopRoutes = routes
    }

    func loadGTFSMapStops(location _: CLLocation?, using gtfsService: any GTFSService) async {
        let region = visibleMapRegion ?? cameraRegion
        await loadGTFSMapStops(region: region, using: gtfsService)
    }

    func updateVisibleMapRegion(_ region: MKCoordinateRegion, using gtfsService: any GTFSService) async {
        guard let region = sanitized(region) else { return }
        visibleMapRegion = region
        await loadGTFSMapStops(region: region, using: gtfsService)
    }

    private func loadGTFSMapStops(region: MKCoordinateRegion, using gtfsService: any GTFSService) async {
        guard let region = sanitized(region) else { return }
        let latitudeMeters = region.span.latitudeDelta * 111_320
        let longitudeMeters = region.span.longitudeDelta * 111_320 * cos(region.center.latitude * .pi / 180)
        let radius = max(500, min(8_000, max(latitudeMeters, longitudeMeters) * 0.75))
        gtfsMapStops = await gtfsService.nearbyStops(
            to: LocationPoint(latitude: region.center.latitude, longitude: region.center.longitude),
            radiusMeters: radius,
            limit: 500
        )
    }

    func selectStop(
        _ stop: Stop,
        preservingLineDetail: Bool = false,
        using store: RoutePlannerStore = .shared
    ) {
        selectedStopGroup = []
        selectedBikeShareStations = []
        selectedStop = stop
        recentStops = store.recordRecentStop(stop)
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
        if !preservingLineDetail {
            clearLineDetail()
        }
        selectedStopRoutes = []
        departures = []
        offlineScheduledDepartures = []
        selectedDepartureLine = nil
        selectedDeparturePlatform = nil
        departureBoardFilter = TransitBoardFilter()
        departuresErrorMessage = nil
        departuresLastUpdated = nil
        routeErrorMessage = nil
        clearRoute()
        moveCamera(to: anchoredRegion(
            for: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func selectStopGroup(
        _ stops: [Stop],
        bikeShareStations: [BikeShareStation] = []
    ) {
        let uniqueStops = stops.deduplicatedByExactName()
        var seenBikeShareStations = Set<String>()
        let uniqueBikeShareStations = bikeShareStations.filter {
            seenBikeShareStations.insert($0.id).inserted
        }
        guard uniqueStops.count + uniqueBikeShareStations.count > 1 else {
            if let stop = uniqueStops.first {
                selectStop(stop)
            }
            return
        }

        selectedStop = nil
        selectedStopGroup = uniqueStops
        selectedBikeShareStations = uniqueBikeShareStations
        routeOrigin = nil
        routeDestination = nil
        clearLineDetail()
        clearRoute()
        if let coordinate = uniqueStops.first?.location.coordinate
            ?? uniqueBikeShareStations.first?.location.coordinate {
            moveCamera(to: anchoredRegion(
                for: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
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

    func updateSelectedStopRoutes(using gtfsService: any GTFSService) async {
        guard let selectedStop else {
            selectedStopRoutes = []
            return
        }
        let routes = await gtfsService.routes(for: selectedStop)
        selectedStopRoutes = routes.isEmpty ? liveRoutesFromDepartures(for: selectedStop) : routes
    }

    /// Keep the line chips useful when the static feed is unavailable or has
    /// no active service for the current date. The live board already carries
    /// the public line and route identifiers, so it is a safe presentation
    /// fallback until GTFS route metadata becomes available.
    private func liveRoutesFromDepartures(for stop: Stop) -> [TransitRoute] {
        var seen: Set<String> = []
        return departures.compactMap { departure in
            let shortName = departure.lineName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortName.isEmpty else { return nil }
            let id = departure.routeId?.isEmpty == false
                ? departure.routeId!
                : "atp:\(shortName.normalizedForSearch)"
            guard seen.insert(id).inserted else { return nil }
            return TransitRoute(
                id: id,
                shortName: shortName,
                mode: stop.modes.first ?? .unknown,
                operatorName: departure.operatorName,
                dataSource: .atpOpenAPI
            )
        }
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: anchoredRegion(
            for: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }
}

private extension Array {
    func asyncMap<Value: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> Value
    ) async -> [Value] where Element: Sendable {
        await withTaskGroup(of: (Int, Value).self, returning: [Value].self) { group in
            for (index, value) in enumerated() {
                group.addTask { (index, await transform(value)) }
            }
            var result = Array<Value?>(repeating: nil, count: count)
            for await (index, value) in group { result[index] = value }
            return result.compactMap(\.self)
        }
    }
}
