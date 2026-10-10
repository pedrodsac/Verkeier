import CoreLocation
import MapKit
import SwiftUI

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

        // Compare value inputs before constructing hundreds of NSObject pins.
        view.update(state: state)
    }

    final class MapContainerView: UIView {
        private let coordinator: Coordinator
        private var mapView: MKMapView?
        private var state: MapViewState?
        private var appliedState: MapViewState?
        private var appliedCameraUpdateToken: Int?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            clipsToBounds = true
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
                (view: MapContainerView, _: UITraitCollection) in
                if let mapView = view.mapView { view.coordinator.routeContent.refreshAppearance(in: mapView) }
            }
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                (view: MapContainerView, _: UITraitCollection) in
                if let mapView = view.mapView { view.coordinator.routeContent.layout(in: mapView) }
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(state: MapViewState) {
            guard self.state != state else { return }
            self.state = state
            // Layout creates the MKMapView once valid bounds arrive. Content
            // changes can be applied directly without requesting another layout.
            applyStateIfPossible()
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
            applyStateIfPossible()
            if let mapView { coordinator.routeContent.layout(in: mapView) }
        }

        private func applyStateIfPossible() {
            guard let mapView, let state, bounds.width > 0, bounds.height > 0 else { return }
            guard appliedState != state else { return }
            let previous = appliedState

            if appliedCameraUpdateToken != state.cameraUpdateToken {
                coordinator.isApplyingRegion = true
                mapView.setRegion(state.region, animated: appliedCameraUpdateToken != nil)
                appliedCameraUpdateToken = state.cameraUpdateToken
            }

            let showsPins = !state.hideMapPins && state.routeOverlay == nil
            let showedPins = previous.map { !$0.hideMapPins && $0.routeOverlay == nil }
            let visibilityChanged = showedPins != showsPins
            if visibilityChanged || previous?.liveStops != state.liveStops
                || previous?.gtfsStops != state.gtfsStops
                || previous?.selectedStopId != state.selectedStopId
                || previous?.favouriteStopIds != state.favouriteStopIds
                || previous?.alertStopIds != state.alertStopIds {
                let annotations = showsPins
                    ? state.liveStops.map { StopMapAnnotation(stop: $0, layer: .liveNearby) }
                        + state.gtfsStops.map { StopMapAnnotation(stop: $0, layer: .gtfs) }
                    : []
                coordinator.syncAnnotations(annotations, in: mapView)
            }
            if previous?.routeOverlay != state.routeOverlay {
                coordinator.routeContent.sync(state.routeOverlay, in: mapView)
            }
            if visibilityChanged || previous?.bikeShareStations != state.bikeShareStations {
                let bikes = showsPins ? state.bikeShareStations.map(BikeShareMapAnnotation.init) : []
                coordinator.syncBikeShareAnnotations(bikes, in: mapView)
            }
            appliedState = state
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
        private var bikeShareAnnotationsByKey: [String: BikeShareMapAnnotation] = [:]
        let routeContent = RouteMapContent()
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

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            routeContent.scheduleLayout(in: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            routeContent.layout(in: mapView)
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
            if let view = routeContent.view(for: annotation, in: mapView) { return view }

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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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

            return routeContent.renderer(for: polyline, traits: mapView.traitCollection)
                ?? MKOverlayRenderer(overlay: overlay)
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
