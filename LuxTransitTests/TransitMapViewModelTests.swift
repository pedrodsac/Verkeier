import CoreLocation
import Foundation
import Testing

@testable import LuxTransit

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
        #expect(viewModel.routeErrorMessage == "Choose a destination stop first.")
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

    @Test func showMoreRouteOptionsRevealsThreeMoreAndThenShowsStatusMessage() {
        let destination = makeStop(id: "stop-1")
        let viewModel = TransitMapViewModel()
        viewModel.selectStop(destination)
        viewModel.routeOptions = (0..<8).map { index in
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
        #expect(viewModel.routeStatusMessage == "No later public transport options were found.")
    }

    @Test func missedPreferredRouteFallsBackToNextViableOption() async {
        let baseNow = Date(timeIntervalSince1970: 10_000)
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
            arrival: baseNow.addingTimeInterval(1_200),
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
                    departureTime: Date(timeIntervalSince1970: 1_000),
                    arrivalTime: Date(timeIntervalSince1970: 1_600),
                    distanceMeters: 2_880
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
        routeName: String
    ) -> RouteOption {
        let plan = RoutePlan(
            id: id,
            origin: LocationPoint(name: "Current Location", latitude: 49.61, longitude: 6.13),
            destination: destination.location,
            expectedTravelTime: arrival.timeIntervalSince(departure),
            distanceMeters: 3200,
            legs: [
                RoutePlan.Leg(
                    id: "\(id)-transit",
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
                    departureTime: departure,
                    arrivalTime: arrival,
                    scheduledDepartureTime: departure,
                    scheduledArrivalTime: arrival,
                    distanceMeters: 3200
                )
            ],
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
            scheduledDeparture: Date(timeIntervalSince1970: 1_000),
            platform: platform,
            dataSource: .mock
        )
    }
}

private enum MockRouteError: Error {
    case unavailable
}

private final class MockRouteService: RouteService, @unchecked Sendable {
    private let result: Result<RouteCalculation, Error>
    private(set) var calculateCallCount = 0

    init(result: Result<RouteCalculation, Error>) {
        self.result = result
    }

    func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RouteCalculation {
        calculateCallCount += 1
        return try result.get()
    }

    func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}
