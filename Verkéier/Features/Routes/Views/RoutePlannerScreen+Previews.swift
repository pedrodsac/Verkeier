import SwiftUI

// MARK: - Previews

#if DEBUG
#Preview("Route Options") {
    routePreview { models in
        let planner = models.routePlanner
        planner.routeDestination = RoutePlace(stop: .previewDestinationStop, source: .selectedStop)
        planner.commutePresets = [
            RouteCommutePreset(
                title: "Kirchberg",
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .preset)
            )
        ]
        planner.routeOptions = [.previewTramRoute, .previewBusRoute]
        planner.selectedRouteOptionID = "tram-route"
        planner.routeStatusMessage = "Fastest option from your current location."
        models.favourites.favouriteStops = [.previewDestinationStop]
    }
}

#Preview("Calculating (skeleton)") {
    routePreview { models in
        models.routePlanner.routeDestination = RoutePlace(stop: .previewDestinationStop, source: .selectedStop)
        models.routePlanner.routeLoadingPhase = .calculating
    }
}

#Preview("Waiting For Location") {
    routePreview { models in
        models.routePlanner.routeDestination = RoutePlace(stop: .previewDestinationStop, source: .selectedStop)
        models.routePlanner.routeLoadingPhase = .waitingForLocation
    }
}

#Preview("Empty state") {
    routePreview { models in
        models.favourites.favouriteStops = [.previewDestinationStop]
        models.map.nearbyStops = [
            .previewDestinationStop,
            Stop(
                id: "stop-clausen",
                name: "Clausen",
                locality: "Clausen",
                location: LocationPoint(id: "clausen", name: "Clausen", latitude: 49.6116, longitude: 6.132),
                modes: [.bus],
                dataSource: .mock
            ),
        ]
    }
}

#Preview("Error state") {
    routePreview { models in
        models.routePlanner.routeDestination = RoutePlace(stop: .previewDestinationStop, source: .selectedStop)
        models.routePlanner.routeErrorMessage =
            "No public transport routes found between these locations. Try adjusting your destination."
    }
}

#Preview("Route Timeline") {
    let models = FeatureModels()
    models.routePlanner.routeDestination = RoutePlace(stop: .previewDestinationStop, source: .selectedStop)
    models.routePlanner.routeOptions = [.previewTramRoute, .previewBusRoute]
    models.routePlanner.selectedRouteOptionID = "tram-route"
    return NavigationStack {
        RouteTimelineView()
    }
    .previewEnvironment(models)
}

// MARK: Preview data

@MainActor
private func routePreview(_ configure: (FeatureModels) -> Void) -> some View {
    let models = FeatureModels()
    configure(models)
    return NavigationStack {
        RoutePlannerScreen()
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .previewEnvironment(models)
}

private extension Stop {
    static var previewDestinationStop: Stop {
        Stop(
            id: "stop-luxexpo",
            name: "Luxexpo",
            locality: "Kirchberg",
            location: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
            modes: [.tram, .bus],
            dataSource: .mock
        )
    }
}

private extension RouteOption {
    static var previewTramRoute: RouteOption {
        RouteOption(
            id: "tram-route",
            plan: RoutePlan(
                id: "tram-plan",
                origin: LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319),
                destination: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                expectedTravelTime: 18 * 60,
                distanceMeters: 4300,
                legs: [
                    RoutePlan.Leg(
                        id: "walk-to-tram",
                        mode: .walking,
                        instruction: "Walk to Hamilius",
                        transportKind: .walking,
                        origin: LocationPoint(
                            id: "origin",
                            name: "Current Location",
                            latitude: 49.6116,
                            longitude: 6.1319
                        ),
                        destination: LocationPoint(
                            id: "hamilius",
                            name: "Hamilius",
                            latitude: 49.6111,
                            longitude: 6.1275
                        ),
                        departureTime: Date(),
                        arrivalTime: Date().addingTimeInterval(4 * 60),
                        distanceMeters: 350
                    ),
                    RoutePlan.Leg(
                        id: "tram-leg",
                        mode: .tram,
                        instruction: "Take tram T1 toward Luxexpo",
                        transportKind: .transit,
                        routeName: "T1",
                        origin: LocationPoint(
                            id: "hamilius",
                            name: "Hamilius",
                            latitude: 49.6111,
                            longitude: 6.1275
                        ),
                        destination: LocationPoint(
                            id: "luxexpo",
                            name: "Luxexpo",
                            latitude: 49.6329,
                            longitude: 6.1746
                        ),
                        departureTime: Date().addingTimeInterval(6 * 60),
                        arrivalTime: Date().addingTimeInterval(18 * 60),
                        realtimeDepartureTime: Date().addingTimeInterval(7 * 60),
                        realtimeArrivalTime: Date().addingTimeInterval(19 * 60),
                        distanceMeters: 3950,
                        platform: "2",
                        delayMinutes: 1,
                        liveStatus: .live
                    ),
                ],
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }

    static var previewBusRoute: RouteOption {
        RouteOption(
            id: "bus-route",
            plan: RoutePlan(
                id: "bus-plan",
                origin: LocationPoint(id: "origin", name: "Current Location", latitude: 49.6116, longitude: 6.1319),
                destination: LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746),
                expectedTravelTime: 24 * 60,
                distanceMeters: 4800,
                legs: [
                    RoutePlan.Leg(
                        id: "bus-leg",
                        mode: .bus,
                        instruction: "Take bus 16 toward Kirchberg",
                        transportKind: .transit,
                        routeName: "16",
                        origin: LocationPoint(
                            id: "origin",
                            name: "Current Location",
                            latitude: 49.6116,
                            longitude: 6.1319
                        ),
                        destination: LocationPoint(
                            id: "luxexpo",
                            name: "Luxexpo",
                            latitude: 49.6329,
                            longitude: 6.1746
                        ),
                        departureTime: Date().addingTimeInterval(9 * 60),
                        arrivalTime: Date().addingTimeInterval(24 * 60),
                        distanceMeters: 4800
                    )
                ],
                dataSource: .mock
            ),
            mapOverlay: nil
        )
    }
}
#endif
