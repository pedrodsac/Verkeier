import CoreLocation
import MapKit
import Observation

/// The map camera and the stops around the rider: live nearby stops, timetable
/// stops in the visible region, and a tapped cluster of stops.
@MainActor @Observable
final class MapModel {
    var cameraRegion: MKCoordinateRegion
    var cameraUpdateToken = 0
    var visibleMapRegion: MKCoordinateRegion?
    /// Set while waiting for a first location fix the camera should move to.
    var centersOnNextLocation = false

    var selectedStopGroup: [Stop] = []
    var selectedBikeShareStations: [BikeShareStation] = []

    var nearbyStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }
    /// Lines serving each nearby stop, keyed by stop id, for the nearby list.
    var nearbyStopRoutes: [String: [TransitRoute]] = [:]
    var nearbyWalkingEstimates: [String: OfflineWalkingEstimate] = [:]
    var isLoadingNearbyStops = false
    var nearbyStopsErrorMessage: String?
    /// Nearby stops with same-named platforms collapsed, for display.
    var distinctNearbyStops: [Stop] {
        nearbyStops.deduplicatedByExactName()
    }

    var gtfsMapStops: [Stop] = [] {
        didSet { rebuildGTFSOnlyMapStops() }
    }
    private(set) var gtfsOnlyMapStops: [Stop] = []
    private(set) var bikeShareStations: [BikeShareStation] = []

    let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.6116, longitude: 6.1319),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )

    @ObservationIgnored private var lastNearbyStopsRequestLocation: CLLocation?
    @ObservationIgnored private var regionUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var nearbyStopsUpdateTask: Task<Void, Never>?
    private let minimumMapSpan = 0.001
    private let nearbyStopsRefreshDistance: CLLocationDistance = 100
    private static let nearbyGTFSFallbackLimit = 6

    init() {
        cameraRegion = defaultRegion
    }
}

// MARK: - Loading

extension MapModel {
    /// Loads the timetable stops in view and the stops around `location`.
    func loadStops(
        near location: CLLocation?,
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService,
        walkingRouter: any WalkingRouting
    ) async {
        await loadGTFSMapStops(using: gtfsService)
        await loadNearbyStops(
            location: location,
            using: liveTransitService,
            gtfsService: gtfsService,
            walkingRouter: walkingRouter
        )
        await loadNearbyStopRoutes(using: gtfsService)
    }

    func loadBikeShareStations(using bikeShareService: any BikeShareService) async {
        await bikeShareService.refreshStaticStations()
        await bikeShareService.refreshAvailability()
        bikeShareStations = await bikeShareService.snapshot()?.stations ?? []
    }

    /// Loads the timetable stops for the region the map came to rest on.
    func regionDidChange(_ region: MKCoordinateRegion, using gtfsService: any GTFSService) {
        regionUpdateTask?.cancel()
        regionUpdateTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            await updateVisibleMapRegion(region, using: gtfsService)
        }
    }

    /// Follows the rider: centres the camera on a first fix when that was
    /// asked for, and reloads the stops around them once the fix settles.
    func locationDidChange(
        to location: CLLocation?,
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService,
        walkingRouter: any WalkingRouting
    ) {
        if centersOnNextLocation, location != nil {
            centerOnUserLocation(location)
            centersOnNextLocation = false
        }
        Task { await loadGTFSMapStops(using: gtfsService) }

        nearbyStopsUpdateTask?.cancel()
        nearbyStopsUpdateTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await loadNearbyStops(
                location: location,
                using: liveTransitService,
                gtfsService: gtfsService,
                walkingRouter: walkingRouter
            )
            await loadNearbyStopRoutes(using: gtfsService)
        }
    }
}

// MARK: - Camera

extension MapModel {
    func moveCamera(to region: MKCoordinateRegion) {
        guard let region = sanitized(region) else { return }
        cameraRegion = region
        visibleMapRegion = region
        cameraUpdateToken += 1
    }

    /// Moves the camera so `coordinate` sits roughly 25% from the top of the
    /// screen, above the bottom sheet instead of behind it.
    func focus(on coordinate: CLLocationCoordinate2D, span: CLLocationDegrees = 0.012) {
        let span = MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        // Map center is at 50% of the height; shifting it south by 25% of the
        // latitude span moves the target coordinate up to ~25% from the top.
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        moveCamera(to: MKCoordinateRegion(center: center, span: span))
    }

    func centerOnUserLocation(_ location: CLLocation?) {
        guard let coordinate = location?.coordinate else { return }
        focus(on: coordinate, span: 0.018)
    }

    /// Fits the camera to a trip's route, leaving room for the sheet below it.
    func fit(trip coordinates: [RouteMapCoordinate]) {
        guard let first = coordinates.first else { return }
        let rect = coordinates.dropFirst().reduce(
            MKMapRect(origin: MKMapPoint(first.coordinate), size: .init(width: 0, height: 0))
        ) {
            $0.union(MKMapRect(origin: MKMapPoint($1.coordinate), size: .init(width: 0, height: 0)))
        }
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta = max(0.008, region.span.latitudeDelta * 2.5)
        region.span.longitudeDelta = max(0.008, region.span.longitudeDelta * 1.25)
        region.center.latitude -= region.span.latitudeDelta * 0.25
        moveCamera(to: region)
    }

    func sanitized(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
        let latitude = region.center.latitude
        let longitude = region.center.longitude
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta

        guard latitude.isFinite,
            longitude.isFinite,
            latitudeDelta.isFinite,
            longitudeDelta.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            latitudeDelta > 0,
            longitudeDelta > 0
        else {
            return nil
        }

        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latitudeDelta, minimumMapSpan), 2.0),
                longitudeDelta: min(max(longitudeDelta, minimumMapSpan), 2.0)
            )
        )
    }
}

// MARK: - Stop groups

extension MapModel {
    enum StopGroupSelection {
        /// The cluster holds several stops or stations and is now selected.
        case group
        /// The cluster holds a single stop, which should be opened directly.
        case singleStop(Stop)
        /// Nothing in the cluster can be opened.
        case none
    }

    func selectStopGroup(_ stops: [Stop], bikeShareStations: [BikeShareStation]) -> StopGroupSelection {
        let uniqueStops = stops.deduplicatedByExactName()
        var seenBikeShareStations = Set<String>()
        let uniqueBikeShareStations = bikeShareStations.filter {
            seenBikeShareStations.insert($0.id).inserted
        }
        guard uniqueStops.count + uniqueBikeShareStations.count > 1 else {
            return uniqueStops.first.map(StopGroupSelection.singleStop) ?? .none
        }

        selectedStopGroup = uniqueStops
        selectedBikeShareStations = uniqueBikeShareStations
        if let coordinate = uniqueStops.first?.location.coordinate
            ?? uniqueBikeShareStations.first?.location.coordinate
        {
            focus(on: coordinate)
        }
        return .group
    }

    func clearStopGroup() {
        selectedStopGroup = []
        selectedBikeShareStations = []
    }
}

// MARK: - Nearby stops

extension MapModel {
    func loadNearbyStops(
        location: CLLocation?,
        using liveTransitService: any LiveTransitService,
        gtfsService: any GTFSService,
        walkingRouter: any WalkingRouting,
        force: Bool = false
    ) async {
        let requestLocation =
            location
            ?? CLLocation(
                latitude: defaultRegion.center.latitude,
                longitude: defaultRegion.center.longitude
            )
        guard force || shouldRefreshNearbyStops(for: requestLocation) else { return }
        lastNearbyStopsRequestLocation = requestLocation
        isLoadingNearbyStops = true
        nearbyStops = []
        nearbyWalkingEstimates = [:]
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
                if liveStops.isEmpty {
                    nearbyStops = await gtfsFallbackStops(near: point, using: gtfsService)
                    if nearbyStops.isEmpty {
                        nearbyStopsErrorMessage = "Nearby stops could not be loaded."
                    }
                } else {
                    nearbyStops = await liveStops.asyncMap { liveStop in
                        await gtfsService.matchLiveStop(liveStop)
                            ?? Stop(
                                id: "hafas:\(liveStop.stationID)",
                                name: liveStop.name,
                                location: liveStop.location,
                                modes: liveStop.modes,
                                dataSource: .atpOpenAPI,
                                hafasStationIDs: [liveStop.stationID]
                            )
                    }
                }
            } catch {
                nearbyStops = await gtfsFallbackStops(near: point, using: gtfsService)
                if nearbyStops.isEmpty {
                    nearbyStopsErrorMessage = "Nearby stops could not be loaded."
                }
            }
        } else {
            nearbyStops = await gtfsFallbackStops(near: point, using: gtfsService)
            if nearbyStops.isEmpty {
                nearbyStopsErrorMessage = "The timetable is still being prepared."
            }
        }
        await refineNearbyWalkingEstimates(from: point, using: walkingRouter)
        isLoadingNearbyStops = false
    }

    /// Loads the lines serving each nearby stop so the nearby list can show
    /// "12 · 14 · 25" rather than just a mode label.
    func loadNearbyStopRoutes(using gtfsService: any GTFSService) async {
        var routes: [String: [TransitRoute]] = [:]
        for stop in nearbyStops {
            routes[stop.id] = await gtfsService.routes(for: stop)
        }
        nearbyStopRoutes = routes
    }

    private func shouldRefreshNearbyStops(for location: CLLocation) -> Bool {
        guard let lastNearbyStopsRequestLocation else { return true }
        return location.distance(from: lastNearbyStopsRequestLocation) >= nearbyStopsRefreshDistance
    }

    private func gtfsFallbackStops(
        near location: LocationPoint,
        using gtfsService: any GTFSService
    ) async -> [Stop] {
        await gtfsService.nearbyStops(
            to: location,
            radiusMeters: 1_500,
            limit: Self.nearbyGTFSFallbackLimit
        )
    }

    /// Calculates one source-to-many matrix after the cheap geographic
    /// prefilter and then reranks the already-visible nearby candidates.
    private func refineNearbyWalkingEstimates(
        from origin: LocationPoint,
        using walkingRouter: any WalkingRouting
    ) async {
        let candidates = NearbyStopPrefilter().destinations(from: nearbyStops, origin: origin)
        guard !candidates.isEmpty,
            let estimates = try? await walkingRouter.estimates(from: origin, to: candidates)
        else { return }

        let estimatesByStopID = Dictionary(
            estimates.map { ($0.destinationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        nearbyWalkingEstimates = estimatesByStopID
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        nearbyStops.sort { lhs, rhs in
            let lhsDuration = estimatesByStopID[lhs.id]?.duration ?? .greatestFiniteMagnitude
            let rhsDuration = estimatesByStopID[rhs.id]?.duration ?? .greatestFiniteMagnitude
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            let lhsDistance = originLocation.distance(
                from: CLLocation(
                    latitude: lhs.location.latitude,
                    longitude: lhs.location.longitude
                )
            )
            let rhsDistance = originLocation.distance(
                from: CLLocation(
                    latitude: rhs.location.latitude,
                    longitude: rhs.location.longitude
                )
            )
            return lhsDistance < rhsDistance
        }
    }
}

// MARK: - Timetable stops

extension MapModel {
    func loadGTFSMapStops(using gtfsService: any GTFSService) async {
        await loadGTFSMapStops(region: visibleMapRegion ?? cameraRegion, using: gtfsService)
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

    private func rebuildGTFSOnlyMapStops() {
        // Normalize each name once. The former nested scan repeated Foundation
        // string folding for every GTFS/live pair on the main actor.
        let liveIDs = Set(nearbyStops.map(\.id))
        let liveStopsByName = Dictionary(grouping: nearbyStops) { $0.name.normalizedForSearch }
        let nextStops = gtfsMapStops.filter { gtfsStop in
            guard !liveIDs.contains(gtfsStop.id) else { return false }
            let candidates = liveStopsByName[gtfsStop.name.normalizedForSearch] ?? []
            return !candidates.contains {
                Self.squaredDistance(from: $0.location, to: gtfsStop.location) < 0.000002
            }
        }
        if gtfsOnlyMapStops != nextStops { gtfsOnlyMapStops = nextStops }
    }

    private static func squaredDistance(from lhs: LocationPoint, to rhs: LocationPoint) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
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
