import SwiftUI

private enum EnvironmentDependencyDefaults {
    static let liveActivityManager = LiveActivityManager()
    static let departureReminderService = DepartureReminderService()
    static let disruptionAlertService = DisruptionAlertService()
}

extension EnvironmentValues {
    @Entry var placeSearchService: any PlaceSearchService = LivePlaceSearchService()
    @Entry var gtfsService: any GTFSService = UnavailableGTFSService()
    @Entry var liveTransitService: any LiveTransitService = UnavailableLiveTransitService()
    @Entry var tripDetailService: any TripDetailService = UnavailableTripDetailService()
    @Entry var routeService: any RouteService = MapKitRouteService()
    @Entry var walkingRouter: any WalkingRouting = UnavailableWalkingRouter()
    @Entry var avlClient: any AVLClient = LiveAVLClient(
        feedURL: AppConfiguration.current.avlMessagesURL
    )
    @Entry var liveActivityManager: LiveActivityManager = EnvironmentDependencyDefaults.liveActivityManager
    @Entry var departureReminderService: DepartureReminderService = EnvironmentDependencyDefaults.departureReminderService
    @Entry var disruptionAlertService: DisruptionAlertService = EnvironmentDependencyDefaults.disruptionAlertService
    // ponytail: stubbed — wire when the respective feed/dataset is confirmed.
    @Entry var routeReliabilityService: any RouteReliabilityService = UnavailableRouteReliabilityService()
    @Entry var parkAndRideService: any ParkAndRideService = UnavailableParkAndRideService()
    @Entry var vehiclePositionService: any VehiclePositionService = UnavailableVehiclePositionService()
    @Entry var bikeShareService: any BikeShareService = UnavailableBikeShareService()
    @Entry var stationFacilitiesService: any StationFacilitiesService = UnavailableStationFacilitiesService()
}
