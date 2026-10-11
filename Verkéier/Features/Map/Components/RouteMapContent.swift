import MapKit

/// Owns only route content. Panning, sheet updates, and text-size changes keep
/// polyline and annotation identities; changed geometry replaces one stroke pair.
@MainActor
final class RouteMapContent {
    private var overlay: RouteMapOverlay?
    private var segmentsByID: [String: RouteMapSegment] = [:]
    private var polylinesByID: [String: [MKPolyline]] = [:]
    private var casingPolylines: Set<ObjectIdentifier> = []
    private var segmentsByPolyline: [ObjectIdentifier: RouteMapSegment] = [:]
    private var stopsByID: [String: RouteStopAnnotation] = [:]
    private var shieldsByID: [String: RouteShieldAnnotation] = [:]
    private var layoutTask: Task<Void, Never>?

    func sync(_ overlay: RouteMapOverlay?, in mapView: MKMapView) {
        guard self.overlay != overlay else { return }
        self.overlay = overlay
        syncSegments(overlay?.segments ?? [], in: mapView)
        syncStops(markers(for: overlay), in: mapView)
        syncShields(overlay?.segments ?? [], in: mapView)
        layout(in: mapView)
    }

    private func syncSegments(_ segments: [RouteMapSegment], in mapView: MKMapView) {
        let drawable = segments.filter { $0.coordinates.count >= 2 }
        let nextIDs = Set(drawable.map(\.id))
        for id in Set(polylinesByID.keys).subtracting(nextIDs) {
            if let polylines = polylinesByID.removeValue(forKey: id) {
                remove(polylines, from: mapView)
            }
            segmentsByID.removeValue(forKey: id)
        }
        for segment in drawable {
            guard segmentsByID[segment.id] != segment else { continue }
            let old = polylinesByID[segment.id]
            if let old { remove(old, from: mapView) }
            let polylines: [MKPolyline]
            if segmentsByID[segment.id]?.coordinates == segment.coordinates, let old { polylines = old }
            else {
                let coordinates = segment.coordinates.map(\.coordinate)
                // Native vector renderers each draw one stroke. Keep the wider
                // casing directly below its foreground, sharing source geometry.
                polylines = (0..<2).map { _ in
                    MKPolyline(coordinates: coordinates, count: coordinates.count)
                }
            }
            segmentsByID[segment.id] = segment
            polylinesByID[segment.id] = polylines
            casingPolylines.insert(ObjectIdentifier(polylines[0]))
            for polyline in polylines {
                segmentsByPolyline[ObjectIdentifier(polyline)] = segment
            }
            mapView.addOverlays(polylines, level: .aboveRoads)
        }
        // Context always lies below the highlighted ride, including partial updates.
        let ordered = (drawable.filter { $0.emphasis == .context } + drawable.filter { $0.emphasis != .context })
            .flatMap { polylinesByID[$0.id] ?? [] }
        let routeIndices = mapView.overlays.indices.filter { index in
            segmentsByPolyline[ObjectIdentifier(mapView.overlays[index])] != nil
        }
        for (position, polyline) in ordered.enumerated() {
            guard position < routeIndices.count,
                  let current = mapView.overlays.firstIndex(where: { $0 === polyline }) else { continue }
            let target = routeIndices[position]
            if current != target { mapView.exchangeOverlay(at: current, withOverlayAt: target) }
        }
    }

    private func remove(_ polylines: [MKPolyline], from mapView: MKMapView) {
        mapView.removeOverlays(polylines)
        for polyline in polylines {
            let identity = ObjectIdentifier(polyline)
            segmentsByPolyline.removeValue(forKey: identity)
            casingPolylines.remove(identity)
        }
    }

    private func markers(for overlay: RouteMapOverlay?) -> [RouteMapStopMarker] {
        guard let overlay else { return [] }
        // Retain old transfer payloads, rendering them with the new small circles.
        return overlay.stopMarkers + overlay.transferMarkers.map { transfer in
            RouteMapStopMarker(id: "legacy:\(transfer.id)", name: transfer.title,
                coordinate: transfer.coordinate, segmentIDs: [], mode: .unknown, role: .transfer)
        }
    }

    private func syncStops(_ markers: [RouteMapStopMarker], in mapView: MKMapView) {
        let nextIDs = Set(markers.map(\.id))
        for id in Set(stopsByID.keys).subtracting(nextIDs) {
            if let annotation = stopsByID.removeValue(forKey: id) { mapView.removeAnnotation(annotation) }
        }
        for marker in markers {
            if let existing = stopsByID[marker.id] { existing.update(marker) }
            else {
                let annotation = RouteStopAnnotation(marker: marker)
                stopsByID[marker.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }
    }

    private func syncShields(_ segments: [RouteMapSegment], in mapView: MKMapView) {
        let highlightedRoutes = Set(segments.filter { $0.emphasis == .highlighted }.map { $0.routeId ?? $0.routeShortName ?? $0.id })
        let labeled = segments.filter { segment in
            guard segment.mode != .walking, segment.mode != .bicycle,
                  let name = segment.routeShortName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, segment.coordinates.count >= 2 else { return false }
            return segment.emphasis != .context || !highlightedRoutes.contains(segment.routeId ?? segment.routeShortName ?? segment.id)
        }
        let nextIDs = Set(labeled.map(\.id))
        for id in Set(shieldsByID.keys).subtracting(nextIDs) {
            if let annotation = shieldsByID.removeValue(forKey: id) { mapView.removeAnnotation(annotation) }
        }
        for segment in labeled {
            if let existing = shieldsByID[segment.id] { existing.update(segment) }
            else {
                let annotation = RouteShieldAnnotation(segment: segment)
                shieldsByID[segment.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }
    }

    func renderer(for polyline: MKPolyline, traits: UITraitCollection) -> MKOverlayRenderer? {
        guard let segment = segmentsByPolyline[ObjectIdentifier(polyline)] else { return nil }
        return RouteTraceRenderer(polyline: polyline, segment: segment, traits: traits,
            isCasing: casingPolylines.contains(ObjectIdentifier(polyline)))
    }

    func view(for annotation: any MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        if let stop = annotation as? RouteStopAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: RouteStopAnnotationView.reuseID)
                as? RouteStopAnnotationView ?? RouteStopAnnotationView(annotation: stop, reuseIdentifier: RouteStopAnnotationView.reuseID)
            view.configure(stop, in: mapView)
            return view
        }
        if let shield = annotation as? RouteShieldAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: RouteShieldAnnotationView.reuseID)
                as? RouteShieldAnnotationView ?? RouteShieldAnnotationView(annotation: shield, reuseIdentifier: RouteShieldAnnotationView.reuseID)
            view.configure(shield, traits: mapView.traitCollection)
            return view
        }
        return nil
    }

    func scheduleLayout(in mapView: MKMapView) {
        guard layoutTask == nil, overlay != nil else { return }
        layoutTask = Task { [weak self, weak mapView] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, let mapView else { return }
            self.layout(in: mapView)
        }
    }

    func refreshAppearance(in mapView: MKMapView) {
        // Recreate renderers with resolved colors, retaining the existing geometry.
        let polylines = mapView.overlays.compactMap { $0 as? MKPolyline }
            .filter { segmentsByPolyline[ObjectIdentifier($0)] != nil }
        mapView.removeOverlays(polylines)
        mapView.addOverlays(polylines, level: .aboveRoads)
        layout(in: mapView)
    }

    func layout(in mapView: MKMapView) {
        layoutTask?.cancel()
        layoutTask = nil
        guard overlay != nil, mapView.bounds.width > 0 else { return }
        let traits = mapView.traitCollection
        let stops = markers(for: overlay).compactMap { marker -> RouteTraceLayout.StopInput? in
            guard let annotation = stopsByID[marker.id] else { return nil }
            return .init(id: marker.id, point: mapView.convert(annotation.coordinate, toPointTo: mapView),
                diameter: RouteTraceStyle.diameter(for: marker.role), labelSize: RouteTraceStyle.labelSize(marker.displayName, in: traits),
                isKey: marker.role != .intermediate)
        }
        let shields = shieldsByID.values.sorted { $0.segment.id < $1.segment.id }.map { annotation in
            let points = annotation.segment.coordinates.map { mapView.convert($0.coordinate, toPointTo: mapView) }
            return RouteTraceLayout.ShieldInput(id: annotation.segment.id,
                candidates: RouteTraceLayout.shieldCandidates(points: points, bounds: mapView.bounds.insetBy(dx: 20, dy: 20)),
                size: RouteTraceStyle.shieldSize(annotation.segment.routeShortName ?? "", in: traits))
        }
        let metersPerPoint = mapView.visibleMapRect.width * MKMetersPerMapPointAtLatitude(mapView.centerCoordinate.latitude)
            / mapView.bounds.width
        let result = RouteTraceLayout.layout(bounds: mapView.bounds, stops: stops, shields: shields,
            showsIntermediate: metersPerPoint <= 4)
        for (id, annotation) in stopsByID {
            annotation.placement = result.stops[id]
            (mapView.view(for: annotation) as? RouteStopAnnotationView)?.configure(annotation, in: mapView)
        }
        for (id, annotation) in shieldsByID {
            annotation.isPlaced = result.shields[id] != nil
            if let point = result.shields[id] { annotation.move(to: mapView.convert(point, toCoordinateFrom: mapView)) }
            (mapView.view(for: annotation) as? RouteShieldAnnotationView)?.configure(annotation, traits: traits)
        }
    }
}
