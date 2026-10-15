import MapKit

/// While a trip detail is open the map follows the trip and the sheet drops
/// to medium height. Closing it puts both back where they were.
extension SheetRouter {
    struct TripDetailReturn {
        let region: MKCoordinateRegion
        let detent: SheetDetent
    }

    /// The trip detail on top of the visible navigation stack, if any.
    var tripDetailSelection: TripDetailSelection? {
        if case let .tripDetail(selection) = activePath.last { return selection }
        return nil
    }

    /// The trip detail to keep live. Updates pause while the app is inactive.
    var liveTripDetailSelection: TripDetailSelection? {
        isSceneActive ? tripDetailSelection : nil
    }

    func tripDetailSelectionDidChange(to selection: TripDetailSelection?) {
        let map = models.map
        if let selection {
            if tripDetailReturn == nil {
                tripDetailReturn = TripDetailReturn(region: map.visibleMapRegion ?? map.cameraRegion, detent: detent)
            }
            tripDetailMapDidFit = false
            models.tripDetail.select(selection)
            detent = .medium
        } else {
            models.tripDetail.deactivate()
            if let tripDetailReturn {
                map.moveCamera(to: tripDetailReturn.region)
                detent = tripDetailReturn.detent
            }
            tripDetailReturn = nil
            tripDetailMapDidFit = false
        }
    }

    /// Fits the map to the open trip once, when its route first arrives.
    func fitMapToTripIfNeeded() {
        guard let selection = tripDetailSelection, !tripDetailMapDidFit,
            let snapshot = models.tripDetail.snapshot,
            snapshot.instance == selection.instance
        else { return }
        let coordinates = snapshot.mapOverlay.segments.flatMap(\.coordinates)
        guard !coordinates.isEmpty else { return }
        tripDetailMapDidFit = true
        models.map.fit(trip: coordinates)
    }
}
