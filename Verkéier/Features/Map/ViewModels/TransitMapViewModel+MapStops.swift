import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
    func requestLocation(using locationService: LocationService) {
        locationService.requestWhenInUseAuthorization()
    }

    func loadNearbyStops(using atpClient: any ATPClient, location: CLLocation?) async {
        isLoadingNearbyStops = true
        nearbyStopsErrorMessage = nil

        let coordinate = location?.coordinate ?? defaultRegion.center

        do {
            nearbyStops = try await atpClient.nearbyStops(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            nearbyStops = []
            nearbyStopsErrorMessage = "Nearby stops could not be loaded."
        }

        isLoadingNearbyStops = false
    }

    /// Loads the lines serving each nearby stop, with bounded concurrency, so
    /// the nearby list can show "12 · 14 · 25" rather than just a mode label.
    func loadNearbyStopRoutes(using gtfsService: any GTFSService) async {
        let stops = nearbyStops
        guard !stops.isEmpty else {
            nearbyStopRoutes = [:]
            return
        }

        var result: [String: [TransitRoute]] = [:]
        await withTaskGroup(of: (String, [TransitRoute]).self) { group in
            var iterator = stops.makeIterator()
            for _ in 0 ..< min(nearbyRouteConcurrencyLimit, stops.count) {
                guard let stop = iterator.next() else { break }
                group.addTask { await (stop.id, gtfsService.routesForStop(id: stop.id)) }
            }

            while let (id, routes) = await group.next() {
                if !routes.isEmpty { result[id] = routes }
                if let stop = iterator.next() {
                    group.addTask { await (stop.id, gtfsService.routesForStop(id: stop.id)) }
                }
            }
        }
        nearbyStopRoutes = result
    }

    func loadGTFSMapStops(using gtfsService: any GTFSService, location _: CLLocation?) async {
        let region = visibleMapRegion ?? cameraRegion
        await loadGTFSMapStops(using: gtfsService, region: region)
    }

    func updateVisibleMapRegion(_ region: MKCoordinateRegion, using gtfsService: any GTFSService) async {
        guard let region = sanitized(region) else { return }
        visibleMapRegion = region
        await loadGTFSMapStops(using: gtfsService, region: region)
    }

    private func loadGTFSMapStops(using gtfsService: any GTFSService, region: MKCoordinateRegion) async {
        guard let region = sanitized(region) else { return }
        let coordinate = region.center
        let center = LocationPoint(
            name: "Visible map center",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        gtfsMapStops = await gtfsService.stopsForMap(
            center: center,
            latitudeDelta: max(region.span.latitudeDelta, defaultRegion.span.latitudeDelta),
            longitudeDelta: max(region.span.longitudeDelta, defaultRegion.span.longitudeDelta),
            limit: 180
        )
    }

    func selectStop(_ stop: Stop, using store: RoutePlannerStore = .shared) {
        selectedStopGroup = []
        selectedBikeShareStations = []
        selectedStop = stop
        recentStops = store.recordRecentStop(stop)
        routeDestination = RoutePlace(stop: stop, source: .selectedStop)
        clearLineDetail()
        selectedStopRoutes = []
        departures = []
        offlineScheduledDepartures = []
        selectedDepartureLine = nil
        selectedDeparturePlatform = nil
        departuresErrorMessage = nil
        departuresLastUpdated = nil
        routeErrorMessage = nil
        clearRoute()
        sheetContext = .stopDetail
        sheetDetent = .medium
        moveCamera(to: anchoredRegion(
            for: stop.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    func selectStopGroup(
        _ stops: [Stop],
        bikeShareStations: [BikeShareStation] = []
    ) {
        var seen = Set<String>()
        let uniqueStops = stops.filter { seen.insert($0.id).inserted }
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
        sheetContext = .stopGroup
        sheetDetent = .medium

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
        async let gtfsLookup = gtfsService.searchStops(query: query)
        async let mapKitLookup = Self.mapKitStops(matching: query)

        let gtfsResults = await Array(gtfsLookup.prefix(80))
        // Drop MapKit hits that land on top of a GTFS stop we already returned.
        let mapKitResults = await mapKitLookup.filter { place in
            !gtfsResults.contains { Self.areWithin(100, place, $0) }
        }

        // A newer keystroke may have superseded this query while MapKit ran.
        guard query == searchQuery else { return }
        searchResults = gtfsResults + mapKitResults
    }

    func updateSelectedStopRoutes(using gtfsService: any GTFSService) async {
        guard let selectedStop else {
            selectedStopRoutes = []
            return
        }

        let directRoutes = await gtfsService.routesForStop(id: selectedStop.id)
        if !directRoutes.isEmpty {
            selectedStopRoutes = directRoutes
            return
        }

        let matchedStops = await gtfsService.searchStops(query: selectedStop.name)
        let routeCandidateStops = matchedStops
            .filter { $0.name.normalizedForSearch == selectedStop.name.normalizedForSearch }
            .sorted {
                squaredDistance(from: $0.location, to: selectedStop.location)
                    < squaredDistance(from: $1.location, to: selectedStop.location)
            }
        for stop in routeCandidateStops {
            let routes = await gtfsService.routesForStop(id: stop.id)
            if !routes.isEmpty {
                selectedStopRoutes = routes
                return
            }
        }

        selectedStopRoutes = []
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        moveCamera(to: anchoredRegion(
            for: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))
    }
}
