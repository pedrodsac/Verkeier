import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import MobiliteitKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    var sheetPresentationModel: TransitSheetPresentationModel {
        let nearbyStops = map.nearbyStops.deduplicatedByExactName()

        let nearby = NearbyStopsPresentationModel(
            stops: nearbyStops,
            isLoading: map.isLoadingNearbyStops,
            errorMessage: map.nearbyStopsErrorMessage,
            referenceLocation: locationService.currentLocation,
            routesByStopId: map.nearbyStopRoutes,
            walkingEstimatesByStopID: map.nearbyWalkingEstimates
        )

        return TransitSheetPresentationModel(
            favourites: FavouritesPresentationModel(
                stops: favouriteEntities.map { favourite in
                    FavouriteStopPresentationModel(
                        stop: favourite.stop,
                        labels: favourite.labels,
                        departures: favourites.favouriteDepartureBoards[favourite.stopId]
                            ?? FavouriteDepartureBoardSnapshot(),
                        displayLabel: favourite.displayLabel,
                        iconName: favourite.iconName,
                        colorHex: favourite.colorHex
                    )
                },
                isRefreshing: favourites.isLoadingFavouriteDepartures,
                liveDeparturesAvailable: canLoadLiveFavouriteDepartures
            ),
            commute: CommuteDashboardViewModel(
                nearby: nearby,
                recentStops: search.recentStops.deduplicatedByExactName(),
                activeAlertCount: alerts.activeAlertCount,
                suggestedCommutePreset: routePlanner.suggestedCommutePreset,
                specialEvents: SpecialEventCatalog.activeEvents()
            ),
            route: RoutePresentationModel(
                selectedStop: stopDetail.selectedStop,
                origin: routePlanner.routeOrigin,
                destination: routePlanner.routeDestination,
                currentLocation: locationService.currentLocation.map { location in
                    RoutePlace.currentLocation(
                        LocationPoint(
                            name: "Current Location",
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    )
                },
                favouritePlaces: favouriteStops.map { RoutePlace(stop: $0, source: .favourite) },
                nearbyPlaces: nearbyStops.map { RoutePlace(stop: $0, source: .nearby) },
                recentPlaces: routePlanner.recentRoutePlaces,
                commutePresets: routePlanner.commutePresets,
                recentTrips: routePlanner.recentTrips,
                filters: routePlanner.routeFilters,
                planningTime: routePlanner.routePlanningTime,
                routeOptions: routePlanner.routeOptions,
                browsingWindow: routePlanner.routeBrowsingWindow,
                supplementalRouteOptions: routePlanner.supplementalRouteOptions,
                isLoadingEarlierRoutes: routePlanner.isLoadingEarlierRoutes,
                isLoadingLaterRoutes: routePlanner.isLoadingLaterRoutes,
                canLoadEarlierRoutes: routePlanner.canLoadEarlierRoutes,
                canLoadLaterRoutes: routePlanner.canLoadLaterRoutes,
                alerts: alerts.alerts(forRoute: routePlanner.selectedRouteOption),
                legAlerts: alerts.legAlerts(forRoute: routePlanner.selectedRouteOption),
                selectedRouteOptionID: routePlanner.selectedRouteOptionID,
                loadingPhase: routePlanner.routeLoadingPhase,
                errorMessage: routePlanner.routeErrorMessage,
                statusMessage: routePlanner.routeStatusMessage,
                lastCalculatedAt: routePlanner.routeLastCalculatedAt,
                diagnosticRequestID: routePlanner.routeDiagnostics?.requestID,
                resultsRendered: routePlanner.recordRouteResultsRendered
            ),
            lineDetail: LineDetailPresentationModel(
                route: lineDetail.selectedLineDetailRoute,
                detail: lineDetail.selectedLineDetail,
                alerts: alerts.alerts(forLine: lineDetail.selectedLineDetailRoute, detail: lineDetail.selectedLineDetail),
                errorMessage: lineDetail.selectedLineDetailErrorMessage
            ),
            tripDetail: tripDetailViewModel
        )
    }

    static let regularWidthPresentationDetent = PresentationDetent.fraction(1)

    var sheetPresentationDetent: Binding<PresentationDetent> {
        Binding(
            get: {
                // Regular width (iPad) only supports a single detent, so the
                // selection must match it or UIKit throws.
                sizeClass == .compact ? router.detent.presentationDetent : Self.regularWidthPresentationDetent
            },
            set: { presentationDetent in
                guard sizeClass == .compact else { return }
                router.detent = BottomSheetDetent(presentationDetent: presentationDetent)
            }
        )
    }
}
