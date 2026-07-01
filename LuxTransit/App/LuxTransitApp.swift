import SwiftData
import SwiftUI

@main
struct LuxTransitApp: App {
    @State private var locationService = LocationService()
    @AppStorage("debugTransitDataMode") private var debugTransitDataModeRawValue =
        DebugTransitDataMode.normal.rawValue
    @State private var preferences = AppPreferences.shared
    private let configuration: AppConfiguration
    private let gtfsService: any GTFSService
    private let modelContainer: ModelContainer
    @State private var liveActivityManager = LiveActivityManager()
    @State private var departureReminderService = DepartureReminderService()
    @State private var disruptionAlertService = DisruptionAlertService()
    @State private var gtfsUpdateController = GTFSUpdateController()

    init() {
        let configuration = AppConfiguration.current
        self.configuration = configuration
        gtfsService = LocalGTFSService()
        modelContainer = AppModelContainer.make()
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
                .environment(\.departureReminderService, departureReminderService)
                .environment(\.disruptionAlertService, disruptionAlertService)
                .environment(preferences)
                .modelContainer(modelContainer)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .task { GTFSBackgroundRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(GTFSBackgroundRefresh.identifier)) {
            await GTFSBackgroundRefresh.run()
            GTFSBackgroundRefresh.schedule()
        }
    }

    private var debugTransitDataMode: DebugTransitDataMode {
        DebugTransitDataMode(rawValue: debugTransitDataModeRawValue) ?? .normal
    }

    private var atpClient: any ATPClient {
        // Offline mode: no live transit data anywhere (departures, delays, cancellations).
        if preferences.offlineMode {
            return EmptyATPClient()
        }
        return switch debugTransitDataMode {
        case .normal:
            configuration.hasATPAccessId ? LiveATPClient(configuration: configuration) : EmptyATPClient()
        case .sample:
            FixtureATPClient(mode: .sample)
        case .empty:
            FixtureATPClient(mode: .empty)
        case .failure:
            FixtureATPClient(mode: .failure)
        case .disruption:
            FixtureATPClient(mode: .disruption)
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

    private var routeService: any RouteService {
        PublicTransportRouteService(
            gtfsService: gtfsService,
            atpClient: atpClient,
            offlineMode: preferences.offlineMode
        )
    }
}
