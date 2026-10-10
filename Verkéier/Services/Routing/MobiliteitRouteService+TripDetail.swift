import Foundation
import MobiliteitKit

extension MobiliteitRouteService: TripDetailService {
    nonisolated func tripDetail(for selection: TripDetailSelection,
        refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot {
        let databaseURL = try await readyDatabaseURL()
        let router = try await engine.router(for: databaseURL)
        let instance = TransitInstanceIdentity(feedGeneration: selection.instance.feedGeneration,
            tripID: selection.instance.tripID, serviceDate: try GTFSDate(parsing: selection.instance.serviceDate))
        let native: TransitTripSnapshot
        do {
            native = try await router.tripSnapshot(for: instance,
                boardingSequence: selection.boardingSequence, refreshPolicy: refreshPolicy == .forceRefresh ? .forceRefresh : .useCache)
        } catch TransitTripSnapshotError.obsoleteFeed { throw TripDetailError.obsoleteFeed }
        let baseTripID = instance.tripID.range(of: "#frequency-").map { String(instance.tripID[..<$0.lowerBound]) } ?? instance.tripID
        let shape = await gtfsService?.routeShape(for: baseTripID) ?? []
        try Task.checkCancellation()
        let currentRouter = try await engine.router(for: readyDatabaseURL())
        guard router === currentRouter else { throw TripDetailError.obsoleteFeed }
        let stops = native.stops.map { entry in
            func timing(_ value: TransitTripTiming?) -> TripStopTiming? {
                value.map { .init(scheduled: $0.scheduled, realtime: $0.realtime,
                    isHistoricalReport: $0.prognosisType?.uppercased() == "REPORTED",
                    observedAt: $0.observedAt, isCancelled: $0.isCancelled) }
            }
            return TripStopEntry(sequence: entry.sequence,
                stop: MobiliteitGTFSService.stop(entry.stop, liveModes: [selection.mode]),
                arrival: timing(entry.arrival), departure: timing(entry.departure), platform: entry.platform)
        }
        let approximate = shape.count < 2
        let coordinates = approximate ? stops.map { RouteMapCoordinate($0.stop.location) } : shape
        var segments = [RouteMapSegment(id: "full-run", mode: selection.mode,
            routeName: selection.lineName, routeId: selection.routeID, coordinates: coordinates,
            emphasis: .context, isApproximate: approximate, routeShortName: selection.routeShortName)]
        let rideStops = stops.filter { selection.boardingSequence...selection.alightingSequence ~= $0.sequence }
        let rideCoordinates: [RouteMapCoordinate]
        if !approximate, let first = rideStops.first, let last = rideStops.last {
            rideCoordinates = JourneyGeometry.segment(of: shape.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                from: .init(latitude: first.stop.location.latitude, longitude: first.stop.location.longitude),
                to: .init(latitude: last.stop.location.latitude, longitude: last.stop.location.longitude))
                .map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        } else { rideCoordinates = rideStops.map { RouteMapCoordinate($0.stop.location) } }
        if rideCoordinates.count >= 2 {
            segments.append(.init(id: "your-ride", mode: selection.mode,
                routeName: selection.lineName, routeId: selection.routeID, coordinates: rideCoordinates,
                emphasis: .highlighted, isApproximate: approximate, routeShortName: selection.routeShortName))
        }
        return TripDetailSnapshot(instance: selection.instance, stops: stops,
            mapOverlay: RouteMapOverlayBuilder.trip(segments: segments, stops: stops, selection: selection), isApproximateRoute: approximate,
            liveDataAvailable: native.liveDataAvailable, isCancelled: native.isCancelled, fetchedAt: native.fetchedAt)
    }
}
