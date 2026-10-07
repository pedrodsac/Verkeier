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
    private let routeService: any RouteService
    private let walkingRouter: any WalkingRouting
    private let bundledRoutingDatasetInstaller: BundledRoutingDatasetInstaller
    private let modelContainer: ModelContainer
    @State private var liveActivityManager = LiveActivityManager()
    @State private var departureReminderService = DepartureReminderService()
    @State private var disruptionAlertService = DisruptionAlertService()

    init() {
        let configuration = AppConfiguration.current
        self.configuration = configuration
        bikeShareService = JCDecauxBikeShareService(configuration: configuration)
        let gtfsService = MobiliteitGTFSService()
        self.gtfsService = gtfsService
        let liveTransitService = MobiliteitLiveTransitService(proxyURL: configuration.apiProxyURL)
        self.liveTransitService = liveTransitService
        let routingDatasetManager = RoutingDatasetManager()
        let walkingRouter = LocalFirstWalkingRouter(datasetManager: routingDatasetManager)
        self.walkingRouter = walkingRouter
        let bundledRoutingDatasetInstaller = BundledRoutingDatasetInstaller(
            datasetManager: routingDatasetManager
        )
        self.bundledRoutingDatasetInstaller = bundledRoutingDatasetInstaller
        let graphPreparation = Task(priority: .utility) {
            _ = await bundledRoutingDatasetInstaller.installIfNeeded()
            await walkingRouter.prepareLocalGraph()
        }
        let routeService = MobiliteitRouteService(
            gtfsService: gtfsService,
            realtimeClient: liveTransitService.realtimeRoutingClient,
            bikeShareService: bikeShareService,
            walkingRouter: walkingRouter,
            roadRouteProvider: LocalFirstRoadRouteProvider(walkingRouter: walkingRouter),
            graphPreparation: graphPreparation
        )
        #if targetEnvironment(simulator)
        if !SimulatorRouteBenchmark.enabled { routeService.prepareForRouting() }
        #else
        routeService.prepareForRouting()
        #endif
        self.routeService = routeService
        modelContainer = AppModelContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if targetEnvironment(simulator)
                if SimulatorRouteBenchmark.enabled { SimulatorRouteBenchmarkView() }
                else { TransitMapScreen(locationService: locationService) }
                #else
                TransitMapScreen(locationService: locationService)
                #endif
            }
                .environment(\.appConfiguration, configuration)
                .environment(\.routeService, routeService)
                .environment(\.walkingRouter, walkingRouter)
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
}
