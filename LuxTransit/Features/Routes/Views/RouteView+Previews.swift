import SwiftUI

// MARK: - Previews

#if DEBUG
    #Preview("Route Options") {
        ScrollView {
            RouteView(
                viewModel: .previewWithRoutes,
                actions: RouteActions()
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Calculating (skeleton)") {
        ScrollView {
            RouteView(
                viewModel: .previewCalculating,
                actions: RouteActions()
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Waiting For Location") {
        ScrollView {
            RouteView(
                viewModel: .previewWaitingForLocation,
                actions: RouteActions()
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Empty state") {
        ScrollView {
            RouteView(
                viewModel: .previewEmpty,
                actions: RouteActions()
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Error state") {
        ScrollView {
            RouteView(
                viewModel: .previewError,
                actions: RouteActions()
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Route Timeline") {
        ScrollView {
            RouteTimelineView(
                viewModel: .previewWithRoutes,
                openInAppleMaps: {}
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: Preview data

    private extension RoutePresentationModel {
        static var previewWithRoutes: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [RoutePlace(stop: .previewDestinationStop, source: .favourite)],
                nearbyPlaces: [RoutePlace(stop: .previewDestinationStop, source: .nearby)],
                recentPlaces: [],
                commutePresets: [
                    RouteCommutePreset(
                        title: "Kirchberg",
                        origin: nil,
                        destination: RoutePlace(stop: .previewDestinationStop, source: .preset)
                    )
                ],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [.previewTramRoute, .previewBusRoute],
                alerts: [
                    AlertMessage(
                        id: "alert-1",
                        title: "T1 line disruption",
                        body: "Expect longer boarding times between Hamilius and Philharmonie.",
                        severity: .warning,
                        affectedStopIds: [],
                        affectedRouteIds: ["T1"],
                        startsAt: .now,
                        endsAt: nil,
                        dataSource: .mock
                    )
                ],
                selectedRouteOptionID: "tram-route",
                visibleRouteOptionCount: 2,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: "Fastest option from your current location."
            )
        }

        static var previewCalculating: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .calculating,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewWaitingForLocation: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .waitingForLocation,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewEmpty: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: nil,
                origin: nil,
                destination: nil,
                favouritePlaces: [RoutePlace(stop: .previewDestinationStop, source: .favourite)],
                nearbyPlaces: [
                    RoutePlace(stop: .previewDestinationStop, source: .nearby),
                    RoutePlace(
                        title: "Clausen",
                        subtitle: "Clausen",
                        location: LocationPoint(id: "clausen", name: "Clausen", latitude: 49.6116, longitude: 6.132),
                        source: .nearby
                    )
                ],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .idle,
                errorMessage: nil,
                statusMessage: nil
            )
        }

        static var previewError: RoutePresentationModel {
            RoutePresentationModel(
                selectedStop: .previewDestinationStop,
                origin: nil,
                destination: RoutePlace(stop: .previewDestinationStop, source: .selectedStop),
                favouritePlaces: [],
                nearbyPlaces: [],
                recentPlaces: [],
                commutePresets: [],
                filters: RoutePlannerFilters(),
                planningTime: .leaveNow,
                routeOptions: [],
                alerts: [],
                selectedRouteOptionID: nil,
                visibleRouteOptionCount: 0,
                loadingPhase: .idle,
                errorMessage: "No public transport routes found between these locations. Try adjusting your destination.",
                statusMessage: nil
            )
        }
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
                        )
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
