import MobiliteitKit
import SwiftData
import SwiftUI

@main
struct VerkéierApp: App {
    @State private var locationService: LocationService
    @State private var preferences = AppPreferences.shared
    @State private var featureModels: FeatureModels
    @State private var router: SheetRouter
    private let configuration: AppConfiguration
    private let avlClient: any AVLClient
    private let bikeShareService: any BikeShareService
    private let gtfsService: any GTFSService
    private let liveTransitService: any LiveTransitService
    private let routeService: any RouteService
    private let tripDetailService: any TripDetailService
    private let walkingRouter: any WalkingRouting
    private let bundledRoutingDatasetInstaller: BundledRoutingDatasetInstaller
    private let routingOptimisationService: any RoutingOptimisationService
    @State private var launchModel: LaunchOptimisationModel
    private let modelContainer: ModelContainer
    @State private var liveActivityManager = LiveActivityManager()
    @State private var departureReminderService = DepartureReminderService()
    @State private var disruptionAlertService = DisruptionAlertService()

    init() {
        let configuration = AppConfiguration.current
        self.configuration = configuration
        avlClient = LiveAVLClient(feedURL: configuration.avlMessagesURL)
        bikeShareService = JCDecauxBikeShareService(configuration: configuration)
        let gtfsService = MobiliteitGTFSService()
        self.gtfsService = gtfsService
        #if targetEnvironment(simulator) || ROUTING_BENCHMARK
        let liveTransitService = MobiliteitLiveTransitService(
            proxyURL: configuration.apiProxyURL,
            diagnostics: SimulatorRouteBenchmark.enabled ? BenchmarkNetworkRecorder.shared.observer : nil
        )
        #else
        let liveTransitService = MobiliteitLiveTransitService(proxyURL: configuration.apiProxyURL)
        #endif
        self.liveTransitService = liveTransitService
        let routingDatasetManager = RoutingDatasetManager()
        let transferWalkStore = TransferWalkStore.makeDefault()
        let walkingRouter = LocalFirstWalkingRouter(
            datasetManager: routingDatasetManager,
            transferWalkStore: transferWalkStore
        )
        self.walkingRouter = walkingRouter
        let bundledRoutingDatasetInstaller = BundledRoutingDatasetInstaller(
            datasetManager: routingDatasetManager
        )
        self.bundledRoutingDatasetInstaller = bundledRoutingDatasetInstaller
        let graphInstall = Task(priority: .utility) {
            await bundledRoutingDatasetInstaller.installIfNeeded()
        }
        let graphPreparation = Task(priority: .utility) {
            _ = await graphInstall.value
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
        #if targetEnvironment(simulator) || ROUTING_BENCHMARK
        if !SimulatorRouteBenchmark.enabled { routeService.prepareForRouting() }
        #else
        routeService.prepareForRouting()
        #endif
        self.routeService = routeService
        self.tripDetailService = routeService
        let optimisationEnvironment = RoutingOptimisationEnvironment.production(store: transferWalkStore)
        routingOptimisationService =
            optimisationEnvironment.mode == .off
            ? UnavailableRoutingOptimisationService()
            : TransferWalkOptimisationService(
                environment: optimisationEnvironment,
                computer: walkingRouter,
                timetable: gtfsService,
                transferRequests: { [engine = routeService.engine] url in
                    try await engine.router(for: url).transferWalkingRequests()
                },
                graphInstall: graphInstall
            )
        _launchModel = State(
            initialValue: LaunchOptimisationModel(
                initialRequirement: optimisationEnvironment.mode == .off
                    ? .notNeeded : RoutingOptimisationLaunchCheck.requirement(in: optimisationEnvironment),
                onboardingCompleted: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
                background: UIKitBackgroundActivity()
            )
        )
        modelContainer = AppModelContainer.make()
        let locationService = LocationService()
        let featureModels = FeatureModels()
        _locationService = State(initialValue: locationService)
        _featureModels = State(initialValue: featureModels)
        _router = State(
            initialValue: SheetRouter(
                models: featureModels,
                locationService: locationService,
                routeService: routeService,
                gtfsService: gtfsService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if targetEnvironment(simulator) || ROUTING_BENCHMARK
                #if DEBUG
                if RouteTracePreviewData.enabled {
                    RouteTracePreviewHost()
                } else if TripDetailPreviewData.enabled {
                    TripDetailPreviewHost()
                } else if TripContinuationPreviewHost.enabled {
                    TripContinuationPreviewHost()
                } else if SimulatorRouteBenchmark.enabled {
                    SimulatorRouteBenchmarkView()
                } else {
                    LaunchGateView(locationService: locationService, model: launchModel)
                }
                #else
                if SimulatorRouteBenchmark.enabled {
                    SimulatorRouteBenchmarkView()
                } else {
                    LaunchGateView(locationService: locationService, model: launchModel)
                }
                #endif
                #else
                LaunchGateView(locationService: locationService, model: launchModel)
                #endif
            }
            .environment(\.appConfiguration, configuration)
            .environment(\.routeService, routeService)
            .environment(\.tripDetailService, tripDetailService)
            .environment(\.walkingRouter, walkingRouter)
            .environment(\.routingOptimisationService, routingOptimisationService)
            .environment(\.gtfsService, gtfsService)
            .environment(\.liveTransitService, liveTransitService)
            .environment(\.bikeShareService, bikeShareService)
            .environment(\.avlClient, avlClient)
            .environment(\.liveActivityManager, liveActivityManager)
            .environment(\.departureReminderService, departureReminderService)
            .environment(\.disruptionAlertService, disruptionAlertService)
            .environment(preferences)
            .featureModels(featureModels)
            .environment(router)
            .modelContainer(modelContainer)
            .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }
}
