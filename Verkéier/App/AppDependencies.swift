import SwiftUI

private enum EnvironmentDependencyDefaults {
    static let gtfsController = GTFSController()
    static let gtfsUpdateController = GTFSUpdateController(controller: gtfsController)
    static let liveActivityManager = LiveActivityManager()
    static let departureReminderService = DepartureReminderService()
    static let disruptionAlertService = DisruptionAlertService()
}

extension EnvironmentValues {
    @Entry var atpClient: any ATPClient = EmptyATPClient()
    @Entry var gtfsService: any GTFSService = EnvironmentDependencyDefaults.gtfsController
    @Entry var placeSearchService: any PlaceSearchService = LivePlaceSearchService()
    @Entry var gtfsUpdateController: GTFSUpdateController = EnvironmentDependencyDefaults.gtfsUpdateController
    @Entry var routeService: any RouteService = PublicTransportRouteService(
        gtfsService: EnvironmentDependencyDefaults.gtfsController,
        atpClient: EmptyATPClient()
    )
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
