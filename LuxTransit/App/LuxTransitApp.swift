import SwiftData
import SwiftUI

@main
struct LuxTransitApp: App {
    @State private var locationService = LocationService()
    private let configuration: AppConfiguration
    private let atpClient: any ATPClient
    private let gtfsService: any GTFSService
    private let routeService: any RouteService
    private let avlClient: any AVLClient
    @State private var liveActivityManager = LiveActivityManager()
    @State private var gtfsUpdateController = GTFSUpdateController()

    init() {
        let configuration = AppConfiguration.current
        self.configuration = configuration
        if configuration.hasATPAccessId {
            atpClient = LiveATPClient(configuration: configuration)
        } else {
            atpClient = EmptyATPClient()
        }
        gtfsService = LocalGTFSService()
        routeService = MapKitRouteService()
        avlClient = LiveAVLClient(feedURL: configuration.avlMessagesURL)
    }

    var body: some Scene {
        WindowGroup {
            TransitMapScreen(locationService: locationService)
                .environment(\.appConfiguration, configuration)
                .environment(\.atpClient, atpClient)
                .environment(\.gtfsService, gtfsService)
                .environment(\.gtfsUpdateController, gtfsUpdateController)
                .environment(\.routeService, routeService)
                .environment(\.avlClient, avlClient)
                .environment(\.liveActivityManager, liveActivityManager)
                .modelContainer(for: PersistedFavouriteStop.self)
        }
    }
}
