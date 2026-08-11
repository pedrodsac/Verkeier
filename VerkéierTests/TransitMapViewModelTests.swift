import CoreLocation
import Foundation
import Testing
@testable import Verkeier

@MainActor
struct TransitMapViewModelTests {
    @Test func selectingStopClearsDepartureFilters() {
        let viewModel = TransitMapViewModel()
        viewModel.selectedDepartureLine = "line-15"
        viewModel.selectedDeparturePlatform = "2"

        viewModel.selectStop(makeStop(id: "stop-1"))

        #expect(viewModel.selectedDepartureLine == nil)
        #expect(viewModel.selectedDeparturePlatform == nil)
    }

    @Test func selectingStopGroupShowsChooserAndDeduplicatesStops() {
        let firstStop = makeStop(id: "stop-1")
        let secondStop = makeStop(id: "stop-2")
        let viewModel = TransitMapViewModel()

        viewModel.selectStopGroup([firstStop, secondStop, firstStop])

        #expect(viewModel.selectedStop == nil)
        #expect(viewModel.selectedStopGroup.map(\.id) == ["stop-1", "stop-2"])
    }

    @Test func transitSheetRoutesUseExpectedDetents() {
        let mediumRoutes: [TransitSheetRoute] = [
            .stopGroup,
            .stopDetail(makeStop(id: "stop-1")),
            .directions,
            .directionsForPreset("preset-1")
        ]
        let expandedRoutes: [TransitSheetRoute] = [
            .search,
            .routeTimeline("route-1"),
            .lineDetail(route15),
            .alerts
        ]

        #expect(mediumRoutes.allSatisfy { $0.defaultDetent == .medium })
        #expect(expandedRoutes.allSatisfy { $0.defaultDetent == .expanded })
    }

    @Test func routeActivationDoesNotChangeDetent() {
        let detent = BottomSheetDetent.expanded
        var appliedPresetID: String?
        var calculatedRoute = false
        var selectedOptionID: String?
        let coordinator = TransitSheetRouteActivationCoordinator(
            selectStop: { _, _ in },
            loadSelectedStopData: {},
            calculateRoute: { calculatedRoute = true },
            applyCommutePreset: { appliedPresetID = $0 },
            selectRouteOption: { selectedOptionID = $0 },
            prepareLineDetail: { _ in false },
            loadLineDetail: {}
        )

        coordinator.activate(.directionsForPreset("preset-1"), previousRoute: nil)
        #expect(appliedPresetID == "preset-1")
        #expect(calculatedRoute)

        coordinator.activate(.routeTimeline("route-1"), previousRoute: .directions)
        #expect(selectedOptionID == "route-1")

        coordinator.activate(nil, previousRoute: .routeTimeline("route-1"))
        #expect(detent == .expanded)
    }

    @Test func routeActivationPreservesLineDetailWhenOpeningStop() {
        let stop = makeStop(id: "stop-1")
        var preservedLineDetail = false
        var selectedStop: Stop?
        let coordinator = TransitSheetRouteActivationCoordinator(
            selectStop: { stop, preservesLineDetail in
                selectedStop = stop
                preservedLineDetail = preservesLineDetail
            },
            loadSelectedStopData: {},
            calculateRoute: {},
            applyCommutePreset: { _ in },
            selectRouteOption: { _ in },
            prepareLineDetail: { _ in false },
            loadLineDetail: {}
        )

        coordinator.activate(.stopDetail(stop), previousRoute: .lineDetail(route15))

        #expect(selectedStop == stop)
        #expect(preservedLineDetail)
    }

    @Test func routeActivationBackNavigationRestoresLineDetailWithoutReloading() {
        let stop = makeStop(id: "stop-1")
        var loadCount = 0
        var preparedRoute: TransitRoute?
        let coordinator = TransitSheetRouteActivationCoordinator(
            selectStop: { _, _ in },
            loadSelectedStopData: {},
            calculateRoute: {},
            applyCommutePreset: { _ in },
            selectRouteOption: { _ in },
            prepareLineDetail: { route in
                guard preparedRoute != route else { return false }
                preparedRoute = route
                return true
            },
            loadLineDetail: { loadCount += 1 }
        )

        coordinator.activate(.lineDetail(route15), previousRoute: nil)
        coordinator.activate(.stopDetail(stop), previousRoute: .lineDetail(route15))
        coordinator.activate(
            .lineDetail(route15),
            previousRoute: .stopDetail(stop),
            isBackNavigation: true
        )

        #expect(loadCount == 1)
        #expect(preparedRoute == route15)
    }

    @Test func selectingLineFiltersDeparturesToThatLine() {
        let viewModel = configuredViewModel()

        viewModel.toggleDepartureLine(route15)

        #expect(viewModel.selectedDepartureLine == route15.id)
        #expect(viewModel.filteredDepartures.map(\.id) == ["line-15-platform-1", "line-15-platform-2"])
    }

    @Test func selectingPlatformFiltersDeparturesToThatPlatform() {
        let viewModel = configuredViewModel()

        viewModel.selectDeparturePlatform("2")

        #expect(viewModel.selectedDeparturePlatform == "2")
        #expect(viewModel.filteredDepartures.map(\.id) == ["line-15-platform-2", "line-10-platform-2"])
    }

    @Test func refreshFailureKeepsLastSuccessfulDeparturesAndTheirPlatforms() async {
        let viewModel = TransitMapViewModel()
        let stop = makeStop(id: "stop-1")
        let departure = makeDeparture(
            id: "line-15-platform-2",
            routeId: route15.id,
            lineName: "15",
            platform: "2"
        )
        viewModel.selectStop(stop)
        viewModel.departures = [departure]

        await viewModel.loadDepartures(using: FailingATPClient())

        #expect(viewModel.departures == [departure])
        #expect(viewModel.filteredDepartures.first?.platform == "2")
        #expect(viewModel.departuresErrorMessage == "Departures could not be loaded.")
    }

    @Test func refreshWithMissingPlatformUsesUniquePreviousPlatformAsFallback() async {
        let viewModel = TransitMapViewModel()
        let stop = makeStop(id: "stop-1")
        let previous = makeDeparture(
            id: "line-15-platform-2",
            routeId: route15.id,
            lineName: "15",
            platform: "2"
        )
        let refreshed = makeDeparture(
            id: "line-15-refreshed",
            routeId: route15.id,
            lineName: "15",
            platform: nil
        )
        viewModel.selectStop(stop)
        viewModel.departures = [previous]

        await viewModel.loadDepartures(using: StaticATPClient(departures: [refreshed]))

        #expect(viewModel.departures.first?.id == "line-15-refreshed")
        #expect(viewModel.departures.first?.platform == "2")
    }

    @Test func lineAndPlatformFiltersCombine() {
        let viewModel = configuredViewModel()

        viewModel.toggleDepartureLine(route15)
        viewModel.selectDeparturePlatform("2")

        #expect(viewModel.filteredDepartures.map(\.id) == ["line-15-platform-2"])
    }

    @Test func clearingFiltersRestoresAllDepartures() {
        let viewModel = configuredViewModel()

        viewModel.toggleDepartureLine(route15)
        viewModel.selectDeparturePlatform("2")
        viewModel.toggleDepartureLine(route15)
        viewModel.selectDeparturePlatform(nil)

        #expect(viewModel.selectedDepartureLine == nil)
        #expect(viewModel.selectedDeparturePlatform == nil)
        #expect(viewModel.filteredDepartures.map(\.id) == [
            "line-15-platform-1",
            "line-15-platform-2",
            "line-10-platform-2"
        ])
    }

    @Test func selectingLineClearsUnavailablePlatformFilter() {
        let viewModel = configuredViewModel()
        viewModel.selectDeparturePlatform("1")

        viewModel.toggleDepartureLine(route10)

        #expect(viewModel.selectedDepartureLine == route10.id)
        #expect(viewModel.selectedDeparturePlatform == nil)
        #expect(viewModel.availableDeparturePlatforms == ["2"])
        #expect(viewModel.filteredDepartures.map(\.id) == ["line-10-platform-2"])
    }

    @Test func gtfsOnlyMapStopsExcludeEquivalentLiveStops() {
        let viewModel = TransitMapViewModel()
        let liveStop = Stop(
            id: "live-stop",
            name: "Central",
            location: LocationPoint(name: "Central", latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: .atpOpenAPI
        )
        let matchingGTFSStop = Stop(
            id: "gtfs-platform",
            name: "Central",
            location: LocationPoint(name: "Central", latitude: 49.6001, longitude: 6.1001),
            modes: [.bus],
            dataSource: .gtfs
        )
        let distinctGTFSStop = Stop(
            id: "gtfs-other",
            name: "Other",
            location: LocationPoint(name: "Other", latitude: 49.61, longitude: 6.11),
            modes: [.tram],
            dataSource: .gtfs
        )

        viewModel.nearbyStops = [liveStop]
        viewModel.gtfsMapStops = [matchingGTFSStop, distinctGTFSStop]

        #expect(viewModel.gtfsOnlyMapStops.map(\.id) == ["gtfs-other"])
    }

    @Test func calculatingRouteWithSelectedStopAndLocationStoresPlan() async {
        let destination = makeStop(id: "stop-1")
        let routePlan = makeRoutePlan(destination: destination)
        let option = makeRouteOption(id: "route-1", plan: routePlan)
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(routeService.calculateCallCount == 1)
        #expect(viewModel.routePlan == routePlan)
        #expect(viewModel.routeOptions == [option])
        #expect(viewModel.selectedRouteOptionID == option.id)
        #expect(viewModel.visibleRouteOptionCount == 1)
        #expect(viewModel.routeMapOverlay == nil)
        #expect(viewModel.isWaitingForRouteLocation == false)
        #expect(viewModel.isCalculatingRoute == false)
        #expect(viewModel.routeErrorMessage == nil)
    }

    @Test func calculatingRouteWithoutSelectedStopShowsDestinationError() async {
        let option = makeRouteOption(
            id: "unused",
            plan: makeRoutePlan(destination: makeStop(id: "unused"))
        )
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        let viewModel = TransitMapViewModel()

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(routeService.calculateCallCount == 0)
        #expect(viewModel.routePlan == nil)
        #expect(viewModel.isWaitingForRouteLocation == false)
        #expect(viewModel.routeErrorMessage == "Choose a route destination first.")
    }

    @Test func calculatingRouteWithoutLocationWaitsForLocation() async {
        let destination = makeStop(id: "stop-1")
        let option = makeRouteOption(id: "route-1", plan: makeRoutePlan(destination: destination))
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)

        await viewModel.calculateRoute(using: routeService, from: nil)

        #expect(routeService.calculateCallCount == 0)
        #expect(viewModel.routePlan == nil)
        #expect(viewModel.isWaitingForRouteLocation)
        #expect(viewModel.isCalculatingRoute == false)
        #expect(viewModel.routeErrorMessage == nil)
    }

    @Test func calculatingRouteAfterWaitingLocationStoresPlan() async {
        let destination = makeStop(id: "stop-1")
        let routePlan = makeRoutePlan(destination: destination)
        let option = makeRouteOption(id: "route-1", plan: routePlan)
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)

        await viewModel.calculateRoute(using: routeService, from: nil)
        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(routeService.calculateCallCount == 1)
        #expect(viewModel.routePlan == routePlan)
        #expect(viewModel.routeOptions == [option])
        #expect(viewModel.isWaitingForRouteLocation == false)
        #expect(viewModel.routeErrorMessage == nil)
    }

    @Test func selectingNewStopClearsRouteState() async {
        let firstStop = makeStop(id: "stop-1")
        let secondStop = makeStop(id: "stop-2")
        let option = makeRouteOption(id: "route-1", plan: makeRoutePlan(destination: firstStop))
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(firstStop)
        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        viewModel.selectStop(secondStop)

        #expect(viewModel.selectedStop == secondStop)
        #expect(viewModel.routePlan == nil)
        #expect(viewModel.routeOptions.isEmpty)
        #expect(viewModel.routeMapOverlay == nil)
        #expect(viewModel.isWaitingForRouteLocation == false)
        #expect(viewModel.isCalculatingRoute == false)
        #expect(viewModel.routeErrorMessage == nil)
    }

    @Test func routeServiceFailureClearsStaleRouteAndShowsError() async {
        let destination = makeStop(id: "stop-1")
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)
        let option = makeRouteOption(id: "route-1", plan: makeRoutePlan(destination: destination))
        let successfulService = MockRouteService(result: .success(RouteCalculation(
            options: [option],
            selectedOptionID: option.id
        )))
        await viewModel.calculateRoute(
            using: successfulService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        let failingService = MockRouteService(result: .failure(MockRouteError.unavailable))
        await viewModel.calculateRoute(
            using: failingService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(viewModel.routePlan == nil)
        #expect(viewModel.routeOptions.isEmpty)
        #expect(viewModel.routeMapOverlay == nil)
        #expect(viewModel.isWaitingForRouteLocation == false)
        #expect(viewModel.isCalculatingRoute == false)
        #expect(viewModel.routeErrorMessage == "A public transport route could not be calculated.")
    }

    @Test func selectingRouteOptionUpdatesSelectedPlanAndOverlay() async {
        let destination = makeStop(id: "stop-1")
        let firstOption = makeRouteOption(
            id: "route-1",
            plan: makeRoutePlan(destination: destination, routeName: "15"),
            overlay: makeOverlay(id: "overlay-1")
        )
        let secondOption = makeRouteOption(
            id: "route-2",
            plan: makeRoutePlan(destination: destination, routeName: "16"),
            overlay: makeOverlay(id: "overlay-2")
        )
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [firstOption, secondOption],
            selectedOptionID: firstOption.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )
        viewModel.selectRouteOption(id: secondOption.id)

        #expect(viewModel.selectedRouteOptionID == secondOption.id)
        #expect(viewModel.routePlan == secondOption.plan)
        #expect(viewModel.routeMapOverlay == secondOption.mapOverlay)
    }

    @Test func showMoreRouteOptionsRevealsThreeMoreAndThenStopsAtAllAvailableOptions() {
        let destination = makeStop(id: "stop-1")
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)
        viewModel.routeOptions = (0 ..< 8).map { index in
            makeRouteOption(
                id: "route-\(index)",
                plan: makeRoutePlan(destination: destination, routeName: "\(index)")
            )
        }
        viewModel.visibleRouteOptionCount = 5
        viewModel.selectedRouteOptionID = viewModel.routeOptions.first?.id

        viewModel.showMoreRouteOptions()

        #expect(viewModel.visibleRouteOptionCount == 8)
        #expect(viewModel.routeStatusMessage == nil)

        viewModel.showMoreRouteOptions()

        #expect(viewModel.visibleRouteOptionCount == 8)
        #expect(viewModel.routeStatusMessage == nil)
    }

    @Test func missedPreferredRouteFallsBackToNextViableOption() async {
        let baseNow = Date(timeIntervalSince1970: 10000)
        let destination = makeStop(id: "stop-1")
        let missedOption = makeTimedRouteOption(
            id: "route-missed",
            destination: destination,
            departure: baseNow.addingTimeInterval(-300),
            arrival: baseNow.addingTimeInterval(600),
            routeName: "15"
        )
        let nextOption = makeTimedRouteOption(
            id: "route-next",
            destination: destination,
            departure: baseNow.addingTimeInterval(300),
            arrival: baseNow.addingTimeInterval(1200),
            routeName: "16"
        )
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [missedOption, nextOption],
            selectedOptionID: missedOption.id
        )))
        let viewModel = TransitMapViewModel(now: { baseNow })
        viewModel.selectStop(destination)

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(viewModel.selectedRouteOptionID == nextOption.id)
        #expect(viewModel.routePlan == nextOption.plan)
    }

    @Test func selectingStopSetsRouteDestination() {
        let stop = makeStop(id: "stop-1")
        let viewModel = TransitMapViewModel()

        viewModel.selectStop(stop)

        #expect(viewModel.routeDestination?.stopId == stop.id)
        #expect(viewModel.routeDestination?.title == stop.name)
    }

    @Test func routeFiltersPreferFewestTransfersAndMatchingMode() async {
        let destination = makeStop(id: "stop-1")
        let busOption = makeTimedRouteOption(
            id: "route-bus",
            destination: destination,
            departure: Date(timeIntervalSince1970: 1000),
            arrival: Date(timeIntervalSince1970: 1900),
            routeName: "15",
            mode: .bus,
            transferCount: 1
        )
        let tramOption = makeTimedRouteOption(
            id: "route-tram",
            destination: destination,
            departure: Date(timeIntervalSince1970: 1020),
            arrival: Date(timeIntervalSince1970: 2000),
            routeName: "T1",
            mode: .tram,
            transferCount: 0
        )
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [busOption, tramOption],
            selectedOptionID: busOption.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)
        viewModel.updateRouteFilters(RoutePlannerFilters(
            sort: .fewestTransfers,
            modePreference: .tram,
            avoidTightTransfers: false,
            preferAccessible: false
        ))

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(viewModel.routeOptions.map(\.id) == ["route-tram"])
        #expect(viewModel.selectedRouteOptionID == "route-tram")
    }

    @Test func accessiblePreferenceFallsBackWhenNoRouteMatches() async {
        let destination = makeStop(id: "stop-1")
        let busOption = makeTimedRouteOption(
            id: "route-long-walk",
            destination: destination,
            departure: Date(timeIntervalSince1970: 1000),
            arrival: Date(timeIntervalSince1970: 1900),
            routeName: "15",
            mode: .bus,
            transferCount: 2,
            walkingDistance: 1200
        )
        let routeService = MockRouteService(result: .success(RouteCalculation(
            options: [busOption],
            selectedOptionID: busOption.id
        )))
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)
        viewModel.updateRouteFilters(RoutePlannerFilters(
            sort: .fastest,
            modePreference: .any,
            avoidTightTransfers: false,
            preferAccessible: true
        ))

        await viewModel.calculateRoute(
            using: routeService,
            from: CLLocation(latitude: 49.61, longitude: 6.13)
        )

        #expect(viewModel.routeOptions.map(\.id) == ["route-long-walk"])
        #expect(viewModel.routeStatusMessage == "No routes matched all filters. Showing the closest alternatives.")
    }

    @Test func stopDetailAlertsMatchSelectedStopAndServedRoutes() {
        let viewModel = TransitMapViewModel()
        let stop = makeStop(id: "stop-1")
        viewModel.selectStop(stop)
        viewModel.selectedStopRoutes = [route15]
        viewModel.alerts = [
            AlertMessage(
                id: "stop-alert",
                title: "Hamilius disruption",
                body: "Affected stop",
                severity: .warning,
                affectedStopIds: ["stop-1"],
                affectedRouteIds: [],
                startsAt: nil,
                endsAt: nil,
                dataSource: .mock
            ),
            AlertMessage(
                id: "route-alert",
                title: "Line 15 disruption",
                body: "Affected line",
                severity: .warning,
                affectedStopIds: [],
                affectedRouteIds: [route15.id],
                startsAt: nil,
                endsAt: nil,
                dataSource: .mock
            ),
            AlertMessage(
                id: "other-alert",
                title: "Other",
                body: "Unrelated",
                severity: .info,
                affectedStopIds: ["stop-9"],
                affectedRouteIds: ["other"],
                startsAt: nil,
                endsAt: nil,
                dataSource: .mock
            )
        ]

        #expect(viewModel.stopDetailAlerts.map(\.id) == ["stop-alert", "route-alert"])
    }

    @Test func routeLegAlertsMapDisruptionsToAffectedTransitLegs() {
        let destination = makeStop(id: "stop-1")
        let option = makeRouteOption(id: "route-1", plan: makeRoutePlan(destination: destination, routeName: "15"))
        let viewModel = TransitMapViewModel()
        viewModel.routeOptions = [option]
        viewModel.selectedRouteOptionID = option.id
        viewModel.alerts = [
            AlertMessage(
                id: "route-alert", title: "Line 15", body: "", severity: .warning,
                affectedStopIds: [], affectedRouteIds: ["15"], startsAt: nil, endsAt: nil, dataSource: .mock
            ),
            AlertMessage(
                id: "stop-alert", title: "Origin stop", body: "", severity: .warning,
                affectedStopIds: ["origin-stop"], affectedRouteIds: [], startsAt: nil, endsAt: nil, dataSource: .mock
            ),
            AlertMessage(
                id: "unrelated", title: "Other", body: "", severity: .info,
                affectedStopIds: ["zzz"], affectedRouteIds: ["999"], startsAt: nil, endsAt: nil, dataSource: .mock
            )
        ]

        let legAlerts = viewModel.routeLegAlerts
        // Walking access leg (index 0) has no alerts; the transit leg (index 1) matches both.
        #expect(legAlerts["0"] == nil)
        #expect(legAlerts["1"]?.map(\.id).sorted() == ["route-alert", "stop-alert"])
    }

    private func configuredViewModel() -> TransitMapViewModel {
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(makeStop(id: "stop-1"))
        viewModel.selectedStopRoutes = [route15, route10]
        viewModel.departures = [
            makeDeparture(id: "line-15-platform-1", routeId: route15.id, lineName: "15", platform: "1"),
            makeDeparture(id: "line-15-platform-2", routeId: nil, lineName: "15", platform: "2"),
            makeDeparture(id: "line-10-platform-2", routeId: route10.id, lineName: "10", platform: "2")
        ]
        return viewModel
    }

    private var route15: TransitRoute {
        TransitRoute(
            id: "route-15",
            shortName: "15",
            mode: .bus,
            dataSource: .gtfs
        )
    }

    private var route10: TransitRoute {
        TransitRoute(
            id: "route-10",
            shortName: "10",
            mode: .bus,
            dataSource: .gtfs
        )
    }

    private func makeStop(id: String) -> Stop {
        Stop(
            id: id,
            name: "Test Stop",
            location: LocationPoint(name: "Test Stop", latitude: 49.6, longitude: 6.1),
            modes: [.bus],
            dataSource: .mock
        )
    }

    private func makeRoutePlan(destination: Stop, routeName: String = "Test Route") -> RoutePlan {
        RoutePlan(
            id: "route-\(destination.id)",
            origin: LocationPoint(name: "Current Location", latitude: 49.61, longitude: 6.13),
            destination: destination.location,
            expectedTravelTime: 900,
            distanceMeters: 3200,
            legs: [
                RoutePlan.Leg(
                    id: "leg-1-access",
                    mode: .walking,
                    instruction: "Walk to the platform",
                    transportKind: .walking,
                    origin: LocationPoint(name: "Current Location", latitude: 49.61, longitude: 6.13),
                    destination: LocationPoint(name: "Origin Stop", latitude: 49.6105, longitude: 6.1305),
                    departureTime: nil,
                    arrivalTime: nil,
                    distanceMeters: 320
                ),
                RoutePlan.Leg(
                    id: "leg-1-transit",
                    mode: .bus,
                    instruction: "Take \(routeName) to Test Stop",
                    transportKind: .transit,
                    routeName: routeName,
                    routeId: routeName,
                    tripId: "trip-\(routeName)",
                    originStopId: "origin-stop",
                    destinationStopId: destination.id,
                    origin: LocationPoint(name: "Origin Stop", latitude: 49.6105, longitude: 6.1305),
                    destination: destination.location,
                    departureTime: Date(timeIntervalSince1970: 1000),
                    arrivalTime: Date(timeIntervalSince1970: 1600),
                    distanceMeters: 2880
                )
            ],
            dataSource: .mock
        )
    }

    private func makeRouteOption(
        id: String,
        plan: RoutePlan,
        overlay: RouteMapOverlay? = nil
    ) -> RouteOption {
        RouteOption(id: id, plan: plan, mapOverlay: overlay)
    }

    private func makeOverlay(id: String) -> RouteMapOverlay {
        RouteMapOverlay(segments: [
            RouteMapSegment(
                id: id,
                mode: .bus,
                coordinates: [
                    RouteMapCoordinate(latitude: 49.61, longitude: 6.13),
                    RouteMapCoordinate(latitude: 49.6, longitude: 6.1)
                ]
            )
        ])
    }

    private func makeTimedRouteOption(
        id: String,
        destination: Stop,
        departure: Date,
        arrival: Date,
        routeName: String,
        mode: TransportMode = .bus,
        transferCount: Int = 0,
        walkingDistance: Double = 0
    ) -> RouteOption {
        var legs: [RoutePlan.Leg] = []
        if walkingDistance > 0 {
            legs.append(
                RoutePlan.Leg(
                    id: "\(id)-walk",
                    mode: .walking,
                    instruction: "Walk to transfer",
                    transportKind: .walking,
                    origin: LocationPoint(name: "Origin", latitude: 49.61, longitude: 6.13),
                    destination: LocationPoint(name: "Transfer", latitude: 49.6105, longitude: 6.1305),
                    departureTime: departure.addingTimeInterval(-300),
                    arrivalTime: departure,
                    distanceMeters: walkingDistance
                )
            )
        }

        for index in 0 ... transferCount {
            let legDeparture = departure.addingTimeInterval(Double(index) * 300)
            let legArrival = index == transferCount ? arrival : legDeparture.addingTimeInterval(240)
            legs.append(
                RoutePlan.Leg(
                    id: "\(id)-transit-\(index)",
                    mode: mode,
                    instruction: "Take \(routeName) to Test Stop",
                    transportKind: .transit,
                    routeName: routeName,
                    routeId: routeName,
                    tripId: "trip-\(routeName)-\(index)",
                    originStopId: "origin-stop-\(index)",
                    destinationStopId: destination.id,
                    origin: LocationPoint(name: "Origin Stop", latitude: 49.6105, longitude: 6.1305),
                    destination: destination.location,
                    departureTime: legDeparture,
                    arrivalTime: legArrival,
                    scheduledDepartureTime: legDeparture,
                    scheduledArrivalTime: legArrival,
                    distanceMeters: 3200 / Double(transferCount + 1)
                )
            )
        }

        let plan = RoutePlan(
            id: id,
            origin: LocationPoint(name: "Current Location", latitude: 49.61, longitude: 6.13),
            destination: destination.location,
            expectedTravelTime: arrival.timeIntervalSince(departure),
            distanceMeters: 3200,
            legs: legs,
            dataSource: .mock
        )
        return RouteOption(id: id, plan: plan, mapOverlay: nil)
    }

    private func makeDeparture(
        id: String,
        routeId: String?,
        lineName: String,
        platform: String?
    ) -> Departure {
        Departure(
            id: id,
            stopId: "stop-1",
            routeId: routeId,
            lineName: lineName,
            destination: "Central",
            scheduledDeparture: Date(timeIntervalSince1970: 1000),
            platform: platform,
            dataSource: .mock
        )
    }
}

private struct FailingATPClient: ATPClient {
    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        throw ATPClientError.httpStatus(503)
    }

    func departureBoard(stopId _: String) async throws -> [Departure] {
        throw ATPClientError.httpStatus(503)
    }
}

private struct StaticATPClient: ATPClient {
    let departures: [Departure]

    func nearbyStops(latitude _: Double, longitude _: Double) async throws -> [Stop] {
        []
    }

    func departureBoard(stopId _: String) async throws -> [Departure] {
        departures
    }
}

private enum MockRouteError: Error {
    case unavailable
}

private nonisolated final class MockRouteService: RouteService, @unchecked Sendable {
    private let result: Result<RouteCalculation, Error>
    private(set) var calculateCallCount = 0

    init(result: Result<RouteCalculation, Error>) {
        self.result = result
    }

    func calculateRoute(
        from _: LocationPoint, to _: LocationPoint, time _: RoutePlanningTime, filters _: RoutePlannerFilters
    ) async throws -> RouteCalculation {
        calculateCallCount += 1
        return try result.get()
    }

    func openInAppleMaps(from _: LocationPoint, to _: LocationPoint) {}
}
