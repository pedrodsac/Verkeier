import CoreLocation
import MapKit
import SwiftUI

/// The data the map renders from, bundled so the call site passes one value
/// instead of eight positional arguments.
struct MapViewState {
    let region: MKCoordinateRegion
    let cameraUpdateToken: Int
    let liveStops: [Stop]
    let gtfsStops: [Stop]
    let selectedStopId: String?
    let favouriteStopIds: Set<String>
    let alertStopIds: Set<String>
    let bikeShareStations: [BikeShareStation]
    let routeOverlay: RouteMapOverlay?
    let hideMapPins: Bool
}

struct TransitMapView: UIViewRepresentable {
    let state: MapViewState
    let selectStop: (Stop) -> Void
    let selectStopGroup: ([Stop], [BikeShareStation]) -> Void
    let regionDidChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectStop: selectStop,
            selectStopGroup: selectStopGroup,
            regionDidChange: regionDidChange
        )
    }

    func makeUIView(context: Context) -> MapContainerView {
        MapContainerView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: MapContainerView, context: Context) {
        context.coordinator.selectStop = selectStop
        context.coordinator.selectStopGroup = selectStopGroup
        context.coordinator.regionDidChange = regionDidChange
        context.coordinator.selectedStopId = state.selectedStopId
        context.coordinator.favouriteStopIds = state.favouriteStopIds
        context.coordinator.alertStopIds = state.alertStopIds

        let stopAnnotations = !state.hideMapPins && state.routeOverlay == nil
            ? state.liveStops.map {
                StopMapAnnotation(stop: $0, layer: .liveNearby)
            }
            + state.gtfsStops.map {
                StopMapAnnotation(stop: $0, layer: .gtfs)
            }
            : []
        let transferAnnotations = state.routeOverlay?.transferMarkers.map(RouteTransferAnnotation.init) ?? []
        let bikeAnnotations = !state.hideMapPins && state.routeOverlay == nil
            ? state.bikeShareStations.map(BikeShareMapAnnotation.init)
            : []

        view.update(
            snapshot: MapSnapshot(
                region: state.region,
                cameraUpdateToken: state.cameraUpdateToken,
                annotations: stopAnnotations,
                transferAnnotations: transferAnnotations,
                bikeShareAnnotations: bikeAnnotations,
                selectedStopId: state.selectedStopId,
                favouriteStopIds: state.favouriteStopIds,
                alertStopIds: state.alertStopIds,
                routeOverlay: state.routeOverlay,
                hideMapPins: state.hideMapPins
            )
        )
    }

    struct MapSnapshot {
        let region: MKCoordinateRegion
        let cameraUpdateToken: Int
        let annotations: [StopMapAnnotation]
        let transferAnnotations: [RouteTransferAnnotation]
        let bikeShareAnnotations: [BikeShareMapAnnotation]
        let selectedStopId: String?
        let favouriteStopIds: Set<String>
        let alertStopIds: Set<String>
        let routeOverlay: RouteMapOverlay?
        let hideMapPins: Bool

        var key: MapSnapshotKey {
            MapSnapshotKey(
                cameraUpdateToken: cameraUpdateToken,
                annotationKeys: annotations.map(\.key),
                transferAnnotationKeys: transferAnnotations.map(\.key),
                bikeShareAnnotationKeys: bikeShareAnnotations.map {
                    "\($0.key):\($0.station.bikesAvailable ?? -1):\($0.station.docksAvailable ?? -1)"
                },
                selectedStopId: selectedStopId,
                favouriteStopIds: favouriteStopIds,
                alertStopIds: alertStopIds,
                routeOverlay: routeOverlay,
                hideMapPins: hideMapPins
            )
        }
    }

    struct MapSnapshotKey: Equatable {
        let cameraUpdateToken: Int
        let annotationKeys: [String]
        let transferAnnotationKeys: [String]
        let bikeShareAnnotationKeys: [String]
        let selectedStopId: String?
        let favouriteStopIds: Set<String>
        let alertStopIds: Set<String>
        let routeOverlay: RouteMapOverlay?
        let hideMapPins: Bool
    }

    final class MapContainerView: UIView {
        private let coordinator: Coordinator
        private var mapView: MKMapView?
        private var snapshot: MapSnapshot?
        private var appliedSnapshotKey: MapSnapshotKey?
        private var appliedCameraUpdateToken: Int?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(snapshot: MapSnapshot) {
            self.snapshot = snapshot
            setNeedsLayout()
            applySnapshotIfPossible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }

            if mapView == nil {
                let mapView = MKMapView(frame: bounds)
                let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
                configuration.pointOfInterestFilter = MKPointOfInterestFilter(
                    excluding: [.publicTransport]
                )
                mapView.preferredConfiguration = configuration
                mapView.delegate = coordinator
                mapView.showsUserLocation = true
                mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let longPress = UILongPressGestureRecognizer(
                    target: coordinator,
                    action: #selector(Coordinator.handleWalkRingLongPress(_:))
                )
                mapView.addGestureRecognizer(longPress)
                addSubview(mapView)
                self.mapView = mapView
            }

            mapView?.frame = bounds
            applySnapshotIfPossible()
        }

        private func applySnapshotIfPossible() {
            guard let mapView, let snapshot, bounds.width > 0, bounds.height > 0 else { return }
            let snapshotKey = snapshot.key
            guard appliedSnapshotKey != snapshotKey else { return }

            if appliedCameraUpdateToken != snapshot.cameraUpdateToken {
                coordinator.isApplyingRegion = true
                mapView.setRegion(snapshot.region, animated: appliedCameraUpdateToken != nil)
                appliedCameraUpdateToken = snapshot.cameraUpdateToken
            }

            coordinator.syncAnnotations(snapshot.annotations, in: mapView)
            coordinator.syncTransferAnnotations(snapshot.transferAnnotations, in: mapView)
            coordinator.syncBikeShareAnnotations(snapshot.bikeShareAnnotations, in: mapView)
            coordinator.syncRoute(snapshot.routeOverlay, in: mapView)
            appliedSnapshotKey = snapshotKey
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private static let bicycleRouteColor = UIColor.systemTeal
        private static let transitStopClusteringIdentifier = "transit-stops"

        var selectStop: (Stop) -> Void
        var selectStopGroup: ([Stop], [BikeShareStation]) -> Void
        var regionDidChange: (MKCoordinateRegion) -> Void
        var selectedStopId: String?
        var favouriteStopIds: Set<String> = []
        var alertStopIds: Set<String> = []
        var isApplyingRegion = false
        private var annotationsByKey: [String: StopMapAnnotation] = [:]
        private var transferAnnotationsByKey: [String: RouteTransferAnnotation] = [:]
        private var bikeShareAnnotationsByKey: [String: BikeShareMapAnnotation] = [:]
        private var routeOverlay: RouteMapOverlay?
        private var routePolylines: [MKPolyline] = []
        private var routePolylineSegments: [ObjectIdentifier: RouteMapSegment] = [:]
        private var walkRing: MKCircle?
        // ponytail: fixed 10-min ring at ~80 m/min; add a walk-time picker to vary it.
        private let walkRingRadiusMeters: CLLocationDistance = 800

        init(
            selectStop: @escaping (Stop) -> Void,
            selectStopGroup: @escaping ([Stop], [BikeShareStation]) -> Void,
            regionDidChange: @escaping (MKCoordinateRegion) -> Void
        ) {
            self.selectStop = selectStop
            self.selectStopGroup = selectStopGroup
            self.regionDidChange = regionDidChange
        }

        /// Long-press drops (or moves) a walking-radius ring so riders can see
        /// which stops are reachable on foot from an arbitrary point.
        @objc func handleWalkRingLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            if let walkRing {
                mapView.removeOverlay(walkRing)
            }
            let circle = MKCircle(center: coordinate, radius: walkRingRadiusMeters)
            mapView.addOverlay(circle, level: .aboveRoads)
            walkRing = circle
        }

        func syncAnnotations(_ annotations: [StopMapAnnotation], in mapView: MKMapView) {
            let nextKeys = Set(annotations.map(\.key))
            let staleKeys = Set(annotationsByKey.keys).subtracting(nextKeys)
            let staleAnnotations = staleKeys.compactMap { annotationsByKey.removeValue(forKey: $0) }
            mapView.removeAnnotations(staleAnnotations)

            for annotation in annotations {
                if let existing = annotationsByKey[annotation.key] {
                    existing.update(stop: annotation.stop)
                    continue
                }

                annotationsByKey[annotation.key] = annotation
                mapView.addAnnotation(annotation)
            }

            for annotation in annotationsByKey.values {
                if let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                    configure(view, for: annotation)
                }
            }
        }

        func syncTransferAnnotations(
            _ annotations: [RouteTransferAnnotation],
            in mapView: MKMapView
        ) {
            let nextKeys = Set(annotations.map(\.key))
            let staleKeys = Set(transferAnnotationsByKey.keys).subtracting(nextKeys)
            let staleAnnotations = staleKeys.compactMap {
                transferAnnotationsByKey.removeValue(forKey: $0)
            }
            mapView.removeAnnotations(staleAnnotations)

            for annotation in annotations {
                if transferAnnotationsByKey[annotation.key] != nil {
                    continue
                }

                transferAnnotationsByKey[annotation.key] = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func syncBikeShareAnnotations(
            _ annotations: [BikeShareMapAnnotation],
            in mapView: MKMapView
        ) {
            let nextKeys = Set(annotations.map(\.key))
            let staleKeys = Set(bikeShareAnnotationsByKey.keys).subtracting(nextKeys)
            let stale = staleKeys.compactMap { bikeShareAnnotationsByKey.removeValue(forKey: $0) }
            mapView.removeAnnotations(stale)

            for annotation in annotations {
                if let existing = bikeShareAnnotationsByKey[annotation.key] {
                    existing.update(station: annotation.station)
                    if let view = mapView.view(for: existing) as? MKMarkerAnnotationView {
                        view.annotation = existing
                    }
                    continue
                }
                bikeShareAnnotationsByKey[annotation.key] = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func syncRoute(_ overlay: RouteMapOverlay?, in mapView: MKMapView) {
            if routeOverlay == overlay {
                return
            }

            if !routePolylines.isEmpty {
                mapView.removeOverlays(routePolylines)
                routePolylines = []
                routePolylineSegments = [:]
            }

            routeOverlay = overlay

            if let overlay {
                let polylines = overlay.segments.compactMap { segment -> MKPolyline? in
                    var coordinates = segment.coordinates.map(\.coordinate)
                    guard coordinates.count >= 2 else { return nil }
                    let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                    routePolylineSegments[ObjectIdentifier(polyline)] = segment
                    return polyline
                }
                mapView.addOverlays(polylines)
                routePolylines = polylines
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            if isApplyingRegion {
                isApplyingRegion = false
                return
            }

            regionDidChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                let stops = cluster.memberAnnotations.compactMap { annotation in
                    (annotation as? StopMapAnnotation)?.stop
                }
                let bikeShareStations = cluster.memberAnnotations.compactMap { annotation in
                    (annotation as? BikeShareMapAnnotation)?.station
                }
                selectStopGroup(stops, bikeShareStations)
                mapView.deselectAnnotation(annotation, animated: true)
                return
            }

            guard let annotation = annotation as? StopMapAnnotation else { return }
            selectStop(annotation.stop)
            mapView.deselectAnnotation(annotation, animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let annotation = annotation as? RouteTransferAnnotation {
                let identifier = "RouteTransferAnnotation"
                let view =
                    mapView.dequeueReusableAnnotationView(
                        withIdentifier: identifier
                    ) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(
                        annotation: annotation,
                        reuseIdentifier: identifier
                    )
                view.annotation = annotation
                configureTransfer(view, for: annotation)
                return view
            }

            if let annotation = annotation as? BikeShareMapAnnotation {
                let identifier = "BikeShareMapAnnotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.markerTintColor = Self.bicycleRouteColor
                view.glyphImage = UIImage(systemName: "bicycle")
                view.glyphTintColor = .white
                view.titleVisibility = .visible
                view.subtitleVisibility = .visible
                view.displayPriority = .defaultHigh
                view.clusteringIdentifier = Self.transitStopClusteringIdentifier
                view.canShowCallout = true
                return view
            }

            guard let annotation = annotation as? StopMapAnnotation else { return nil }

            let identifier = "StopMapAnnotation"
            let view =
                mapView.dequeueReusableAnnotationView(
                    withIdentifier: identifier
                ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )
            view.annotation = annotation
            configure(view, for: annotation)
            return view
        }

        func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.6)
                renderer.lineWidth = 1.5
                return renderer
            }

            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            let segment = routePolylineSegments[ObjectIdentifier(polyline)]
            let mode = segment?.mode ?? .unknown
            renderer.strokeColor = routeColor(for: segment)
            renderer.lineWidth = mode == .walking ? 2 : 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if mode == .walking {
                renderer.lineDashPattern = [1, 4]
            }
            return renderer
        }

        private func routeColor(for segment: RouteMapSegment?) -> UIColor {
            guard let segment else { return .systemBlue }
            let palette: [UIColor] = switch segment.mode {
            case .bus:
                [.systemBlue, .link, .systemCyan, .systemIndigo]
            case .train:
                [
                    .systemRed,
                    .red,
                    UIColor(red: 0.72, green: 0.08, blue: 0.12, alpha: 1),
                    UIColor(red: 0.95, green: 0.22, blue: 0.18, alpha: 1)
                ]
            case .tram:
                [
                    .systemOrange,
                    UIColor(red: 0.92, green: 0.42, blue: 0.06, alpha: 1),
                    UIColor(red: 0.78, green: 0.31, blue: 0.02, alpha: 1),
                    UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1)
                ]
            case .funicular:
                [.systemTeal]
            case .bicycle:
                [Self.bicycleRouteColor]
            case .walking:
                [.secondaryLabel]
            case .unknown:
                [.systemBlue]
            }

            let routeKey = segment.routeId ?? segment.routeName ?? segment.id
            let index = abs(routeKey.hashValue) % palette.count
            return palette[index]
        }

        private func configureTransfer(
            _ view: MKMarkerAnnotationView,
            for _: RouteTransferAnnotation
        ) {
            view.markerTintColor = .systemIndigo
            view.glyphTintColor = .white
            view.glyphImage = UIImage(systemName: "arrow.triangle.2.circlepath")
            view.titleVisibility = .visible
            view.subtitleVisibility = .hidden
            view.displayPriority = .required
            view.canShowCallout = false
        }

        private func configure(_ view: MKMarkerAnnotationView, for annotation: StopMapAnnotation) {
            let isSelected = selectedStopId == annotation.stop.id
            let isFavourite = favouriteStopIds.contains(annotation.stop.id)
            let hasAlert = alertStopIds.contains(annotation.stop.id)

            view.markerTintColor = markerColor(
                for: annotation.stop,
                isSelected: isSelected,
                isFavourite: isFavourite,
                hasAlert: hasAlert
            )
            view.glyphTintColor = .white
            if hasAlert {
                view.glyphText = "!"
                view.glyphImage = nil
            } else {
                view.glyphText = isFavourite ? "★" : nil
                view.glyphImage = isFavourite ? nil : UIImage(systemName: glyphName(for: annotation.stop))
            }
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.displayPriority = isSelected ? .required : .defaultHigh
            view.canShowCallout = false
            // Native clustering for dense regular stops; selected / favourite /
            // alert markers stay unclustered so they're always visible. Use a
            // unique non-nil identifier for the latter instead of assigning
            // `nil`: on iOS 27's MapKit simulator, clearing this property on a
            // reused marker can throw an Objective-C dictionary exception.
            view.clusteringIdentifier = (isSelected || isFavourite || hasAlert)
                ? "stop-single-\(annotation.key)"
                : Self.transitStopClusteringIdentifier
        }

        private func markerColor(
            for stop: Stop,
            isSelected: Bool,
            isFavourite: Bool,
            hasAlert: Bool
        ) -> UIColor {
            if hasAlert {
                if isSelected { return .systemRed }
                return UIColor(red: 0.82, green: 0.24, blue: 0.16, alpha: 1)
            }
            if isFavourite {
                // Amber/gold, clearly distinct from regular blue stops, regardless
                // of mode. Selected still wins so the active marker reads as active.
                if isSelected { return .systemIndigo }
                return UIColor(red: 0.95, green: 0.75, blue: 0.10, alpha: 1)
            }
            if stop.modes.contains(.train) { return .systemRed }
            if stop.modes.contains(.tram) { return .systemOrange }
            if isSelected { return .systemIndigo }
            return .systemBlue
        }

        private func glyphName(for stop: Stop) -> String {
            if stop.modes.contains(.train) { return "train.side.front.car" }
            if stop.modes.contains(.tram) { return "tram.fill" }
            return "bus.fill"
        }
    }
}
