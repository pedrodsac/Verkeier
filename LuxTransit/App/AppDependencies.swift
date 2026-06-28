import SwiftUI

extension EnvironmentValues {
    @Entry var atpClient: any ATPClient = EmptyATPClient()
    @Entry var gtfsService: any GTFSService = LocalGTFSService()
    @Entry var placeSearchService: any PlaceSearchService = LivePlaceSearchService()
    @Entry var gtfsUpdateController: GTFSUpdateController = .init()
    @Entry var routeService: any RouteService = PublicTransportRouteService(
        gtfsService: LocalGTFSService(),
        atpClient: EmptyATPClient()
    )
    @Entry var avlClient: any AVLClient = LiveAVLClient(
        feedURL: AppConfiguration.current.avlMessagesURL
    )
    @Entry var liveActivityManager: LiveActivityManager = .init()
    @Entry var departureReminderService: DepartureReminderService = .init()
    @Entry var disruptionAlertService: DisruptionAlertService = .init()
    // ponytail: stubbed — wire when the respective feed/dataset is confirmed.
    @Entry var routeReliabilityService: any RouteReliabilityService = UnavailableRouteReliabilityService()
    @Entry var parkAndRideService: any ParkAndRideService = UnavailableParkAndRideService()
}
