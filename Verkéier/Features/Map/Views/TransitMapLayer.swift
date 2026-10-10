import MapKit
import SwiftUI

/// Keeps map-only Observation reads out of the screen's presentation boundary.
/// Search text, departure refreshes, and sheet detents do not alter map content.
struct TransitMapLayer: View {
    @Environment(AppPreferences.self) private var preferences
    let viewModel: TransitMapViewModel
    var tripDetail: TripDetailViewModel? = nil
    let navigation: TransitSheetNavigationState
    let favouriteStopIds: Set<String>
    let bikeShareStations: [BikeShareStation]
    let selectStop: (Stop) -> Void
    let selectStopGroup: ([Stop], [BikeShareStation]) -> Void
    let regionDidChange: (MKCoordinateRegion) -> Void

    var body: some View {
        TransitMapView(
            state: MapViewState(
                region: viewModel.cameraRegion,
                cameraUpdateToken: viewModel.cameraUpdateToken,
                liveStops: mapLiveStops,
                gtfsStops: mapGTFSStops,
                selectedStopId: viewModel.selectedStop?.id,
                favouriteStopIds: favouriteStopIds,
                alertStopIds: Set(viewModel.alerts.flatMap(\.affectedStopIds)),
                bikeShareStations: mapBikeShareStations,
                routeOverlay: mapRouteOverlay,
                hideMapPins: shouldHideMapPins
            ),
            selectStop: selectStop,
            selectStopGroup: selectStopGroup,
            regionDidChange: regionDidChange
        )
        .ignoresSafeArea()
        .accessibilityLabel("Luxembourg transit map")
    }

    var selectedBikeShareStations: [BikeShareStation] {
        guard let option = viewModel.selectedRouteOption else { return [] }
        var seen = Set<String>()
        return option.plan.legs.compactMap { $0.bikeShareDetails }
            .flatMap { [$0.pickupStation, $0.returnStation] }
            .filter { seen.insert($0.id).inserted }
    }

    var mapBikeShareStations: [BikeShareStation] {
        guard preferences.showBikeShareStations, !shouldHideMapPins else { return [] }

        var stations = bikeShareStations
        var indexByID = Dictionary(uniqueKeysWithValues: stations.enumerated().map { ($1.id, $0) })

        for station in selectedBikeShareStations {
            if let index = indexByID[station.id] {
                stations[index] = station
            } else {
                indexByID[station.id] = stations.endIndex
                stations.append(station)
            }
        }

        return stations
    }

    var mapLiveStops: [Stop] {
        guard !shouldHideMapPins else { return [] }
        return viewModel.nearbyStops
            .filter(shouldShowMapStop)
            .deduplicatedByExactName()
    }

    var mapGTFSStops: [Stop] {
        guard !shouldHideMapPins else { return [] }
        let liveStopNames = Set(mapLiveStops.map(\.name))
        return viewModel.gtfsOnlyMapStops
            .filter(shouldShowMapStop)
            .filter { !liveStopNames.contains($0.name) }
            .deduplicatedByExactName()
    }

    private func shouldShowMapStop(_ stop: Stop) -> Bool {
        let hasConfigurableMode = stop.modes.contains {
            $0 == .bus || $0 == .tram || $0 == .train
        }
        guard hasConfigurableMode else { return true }

        return (stop.modes.contains(.bus) && preferences.showBusStops)
            || (stop.modes.contains(.tram) && preferences.showTramStops)
            || (stop.modes.contains(.train) && preferences.showTrainStations)
    }

    var shouldHideMapPins: Bool {
        isShowingRouteDetail || mapRouteOverlay != nil
    }

    var mapRouteOverlay: RouteMapOverlay? {
        switch navigation.activePath.last {
        case .routeTimeline:
            return viewModel.routeMapOverlay
        case let .tripDetail(selection):
            return tripDetail?.snapshot?.instance == selection.instance ? tripDetail?.snapshot?.mapOverlay : nil
        case .lineDetail:
            return viewModel.selectedLineDetail?.mapOverlay
        default:
            return nil
        }
    }

    private var isShowingRouteDetail: Bool {
        if case .routeTimeline = navigation.activePath.last { return true }
        return false
    }
}
