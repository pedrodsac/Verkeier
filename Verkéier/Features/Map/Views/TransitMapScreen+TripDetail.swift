import MapKit
import SwiftUI

extension TransitMapScreen {
    var tripDetailSelection: TripDetailSelection? {
        if case let .tripDetail(selection) = sheetNavigation.activePath.last { return selection }
        return nil
    }

    var activeTripDetailSelection: TripDetailSelection? {
        scenePhase == .active ? tripDetailSelection : nil
    }

    func tripDetailNavigationChanged(to selection: TripDetailSelection?) {
        if let selection {
            if tripDetailReturnRegion == nil {
                tripDetailReturnRegion = viewModel.visibleMapRegion ?? viewModel.cameraRegion
                tripDetailReturnDetent = sheetDetent
            }
            tripDetailCameraDidFit = false
            tripDetailViewModel.select(selection)
            sheetDetent = .medium
        } else {
            tripDetailViewModel.deactivate()
            if let region = tripDetailReturnRegion { viewModel.moveCamera(to: region) }
            if let detent = tripDetailReturnDetent { sheetDetent = detent }
            tripDetailReturnRegion = nil
            tripDetailReturnDetent = nil
            tripDetailCameraDidFit = false
        }
    }

    func fitTripDetailMapIfNeeded() {
        guard tripDetailSelection != nil, !tripDetailCameraDidFit,
              let snapshot = tripDetailViewModel.snapshot,
              snapshot.instance == tripDetailSelection?.instance else { return }
        let coordinates = snapshot.mapOverlay.segments.flatMap(\.coordinates)
        guard let first = coordinates.first else { return }
        let rect = coordinates.dropFirst().reduce(MKMapRect(origin: MKMapPoint(first.coordinate), size: .init(width: 0, height: 0))) {
            $0.union(MKMapRect(origin: MKMapPoint($1.coordinate), size: .init(width: 0, height: 0)))
        }
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta = max(0.008, region.span.latitudeDelta * 2.5)
        region.span.longitudeDelta = max(0.008, region.span.longitudeDelta * 1.25)
        region.center.latitude -= region.span.latitudeDelta * 0.25
        tripDetailCameraDidFit = true
        viewModel.moveCamera(to: region)
    }
}
