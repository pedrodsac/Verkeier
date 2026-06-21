import SwiftUI

extension EnvironmentValues {
    @Entry var atpClient: any ATPClient = EmptyATPClient()
    @Entry var gtfsService: any GTFSService = LocalGTFSService()
    @Entry var gtfsUpdateController: GTFSUpdateController = GTFSUpdateController()
    @Entry var routeService: any RouteService = PublicTransportRouteService(
        gtfsService: LocalGTFSService(),
        atpClient: EmptyATPClient()
    )
    @Entry var avlClient: any AVLClient = LiveAVLClient(
        feedURL: AppConfiguration.current.avlMessagesURL)
    @Entry var liveActivityManager: LiveActivityManager = LiveActivityManager()
    @Entry var departureReminderService: DepartureReminderService = DepartureReminderService()
}
