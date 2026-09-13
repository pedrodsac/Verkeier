import SwiftData
import SwiftUI

@main
struct VerkéierApp: App {
    @State private var locationService = LocationService()
    @AppStorage("debugTransitDataMode") private var debugTransitDataModeRawValue =
        DebugTransitDataMode.normal.rawValue
    @State private var preferences = AppPreferences.shared
    private let configuration: AppConfiguration
    private let bikeShareService: any BikeShareService
    private let gtfsService: any GTFSService
    private let liveTransitService: any LiveTransitService
    private let modelContainer: ModelContainer
    @State private var liveActivityManager = LiveActivityManager()
    @State private var departureReminderService = DepartureReminderService()
    @State private var disruptionAlertService = DisruptionAlertService()

    init() {
        let configuration = AppConfiguration.current
        self.configuration = configuration
        bikeShareService = JCDecauxBikeShareService(configuration: configuration)
        gtfsService = MobiliteitGTFSService()
        liveTransitService = MobiliteitLiveTransitService(proxyURL: configuration.apiProxyURL)
        modelContainer = AppModelContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            TransitMapScreen(locationService: locationService)
                .environment(\.appConfiguration, configuration)
                .environment(\.routeService, routeService)
                .environment(\.gtfsService, gtfsService)
                .environment(\.liveTransitService, liveTransitService)
                .environment(\.bikeShareService, bikeShareService)
                .environment(\.avlClient, avlClient)
                .environment(\.liveActivityManager, liveActivityManager)
                .environment(\.departureReminderService, departureReminderService)
                .environment(\.disruptionAlertService, disruptionAlertService)
                .environment(preferences)
                .modelContainer(modelContainer)
                .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }

    private var avlClient: any AVLClient {
        switch debugTransitDataMode {
        case .normal, .sample:
            LiveAVLClient(feedURL: configuration.avlMessagesURL)
        case .empty:
            EmptyAVLClient()
        case .failure:
            FailingAVLClient()
        case .disruption:
            SevereMockAVLClient()
        }
    }

    private var debugTransitDataMode: DebugTransitDataMode {
        DebugTransitDataMode(rawValue: debugTransitDataModeRawValue) ?? .normal
    }

    private var routeService: any RouteService { MobiliteitRouteService() }
}
