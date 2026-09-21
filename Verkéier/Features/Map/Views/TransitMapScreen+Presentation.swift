import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    var sheetPresentationModel: TransitSheetPresentationModel {
        let nearbyStops = viewModel.nearbyStops.deduplicatedByExactName()

        let nearby = NearbyStopsPresentationModel(
            stops: nearbyStops,
            isLoading: viewModel.isLoadingNearbyStops,
            errorMessage: viewModel.nearbyStopsErrorMessage,
            referenceLocation: locationService.currentLocation,
            routesByStopId: viewModel.nearbyStopRoutes,
            walkingEstimatesByStopID: viewModel.nearbyWalkingEstimates
        )

        return TransitSheetPresentationModel(
            nearby: nearby,
            favourites: FavouritesPresentationModel(
                stops: favouriteEntities.map { favourite in
                    FavouriteStopPresentationModel(
                        stop: favourite.stop,
                        labels: favourite.labels,
                        departures: viewModel.favouriteDepartureBoards[favourite.stopId]
                            ?? FavouriteDepartureBoardSnapshot()
                    )
                },
                isRefreshing: viewModel.isLoadingFavouriteDepartures,
                liveDeparturesAvailable: canLoadLiveFavouriteDepartures
            ),
            stopGroup: StopGroupPresentationModel(
                stops: viewModel.selectedStopGroup.deduplicatedByExactName(),
                bikeShareStations: viewModel.selectedBikeShareStations,
                referenceLocation: locationService.currentLocation,
                routesByStopId: viewModel.nearbyStopRoutes
            ),
            commute: CommuteDashboardViewModel(
                nearby: nearby,
                recentStops: viewModel.recentStops.deduplicatedByExactName(),
                activeAlertCount: viewModel.activeAlertCount,
                suggestedCommutePreset: viewModel.suggestedCommutePreset,
                specialEvents: SpecialEventCatalog.activeEvents()
            ),
            search: SearchPresentationModel(
                results: viewModel.searchResults,
                nearbySuggestions: nearbyStops,
                isLoadingNearbySuggestions: viewModel.isLoadingNearbyStops,
                referenceLocation: locationService.currentLocation,
                recentStops: viewModel.recentStops.deduplicatedByExactName()
            ),
            stopDetail: StopDetailPresentationModel(
                stop: viewModel.selectedStop,
                routes: viewModel.selectedStopRoutes,
                departures: viewModel.departures,
                offlineScheduledDepartures: viewModel.offlineScheduledDepartures,
                alerts: viewModel.stopDetailAlerts,
                selectedLine: viewModel.selectedDepartureLine,
                selectedPlatform: viewModel.selectedDeparturePlatform,
                departureBoardFilter: viewModel.departureBoardFilter,
                isLoadingDepartures: viewModel.isLoadingDepartures,
                errorMessage: viewModel.departuresErrorMessage,
                liveErrorMessage: viewModel.liveTransitErrorMessage,
                lastUpdated: viewModel.departuresLastUpdated,
                isStale: viewModel.areDeparturesStale,
                isFavourite: viewModel.selectedStop.map(isFavourite) ?? false,
                trackedDepartureId: liveActivityManager.trackedDepartureId,
                liveActivityErrorMessage: liveActivityManager.lastErrorMessage,
                liveActivityStaleMessage: liveActivityManager.staleExplanation,
                activeReminder: departureReminderForSelectedStop,
                departureReminderErrorMessage: departureReminderService.lastErrorMessage
            ),
            route: RoutePresentationModel(
                selectedStop: viewModel.selectedStop,
                origin: viewModel.routeOrigin,
                destination: viewModel.routeDestination,
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
                recentPlaces: viewModel.recentRoutePlaces,
                commutePresets: viewModel.commutePresets,
                recentTrips: viewModel.recentTrips,
                filters: viewModel.routeFilters,
                planningTime: viewModel.routePlanningTime,
                routeOptions: viewModel.routeOptions,
                supplementalRouteOptions: viewModel.supplementalRouteOptions,
                isLoadingEarlierRoutes: viewModel.isLoadingEarlierRoutes,
                isLoadingLaterRoutes: viewModel.isLoadingLaterRoutes,
                canLoadEarlierRoutes: viewModel.canLoadEarlierRoutes,
                canLoadLaterRoutes: viewModel.canLoadLaterRoutes,
                alerts: viewModel.routeAlerts,
                legAlerts: viewModel.routeLegAlerts,
                selectedRouteOptionID: viewModel.selectedRouteOptionID,
                loadingPhase: viewModel.routeLoadingPhase,
                errorMessage: viewModel.routeErrorMessage,
                statusMessage: viewModel.routeStatusMessage,
                lastCalculatedAt: viewModel.routeLastCalculatedAt
            ),
            lineDetail: LineDetailPresentationModel(
                route: viewModel.selectedLineDetailRoute,
                detail: viewModel.selectedLineDetail,
                alerts: viewModel.lineDetailAlerts,
                errorMessage: viewModel.selectedLineDetailErrorMessage
            ),
            alerts: AlertsPresentationModel(
                alerts: viewModel.alerts,
                isLoading: viewModel.isLoadingAlerts,
                errorMessage: viewModel.alertsErrorMessage,
                lastUpdated: viewModel.alertsLastUpdated,
                isStale: viewModel.areAlertsStale
            ),
            settings: SettingsPresentationModel(
                configuration: appConfiguration,
                readiness: settingsReadinessSnapshot,
                gtfsStatus: viewModel.gtfsFeedStatus,
                supportBundleText: settingsSupportBundleText,
                debugDataMode: debugTransitDataMode
            )
        )
    }

    var settingsReadinessSnapshot: DataReadinessSnapshot {
        SettingsSupport.readinessSnapshot(
            configuration: appConfiguration,
            gtfsStatus: viewModel.gtfsFeedStatus,
            liveTransitLastUpdated: viewModel.liveTransitLastUpdated,
            liveTransitErrorMessage: viewModel.liveTransitErrorMessage
        )
    }

    var settingsSupportBundleText: String {
        SettingsSupport.supportBundleText(
            appVersion: appVersion,
            readiness: settingsReadinessSnapshot,
            configuration: appConfiguration
        )
    }

    var appVersion: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var debugTransitDataMode: DebugTransitDataMode {
        DebugTransitDataMode(rawValue: debugTransitDataModeRawValue) ?? .normal
    }

    var departureReminderForSelectedStop: SharedTrackedDepartureReminder? {
        guard let selectedStopID = viewModel.selectedStop?.id else { return nil }
        guard let reminder = departureReminderService.activeReminder, reminder.stopId == selectedStopID else {
            return nil
        }
        return reminder
    }

    var sheetPresentationDetent: Binding<PresentationDetent> {
        Binding(
            get: {
                sheetDetent.presentationDetent
            },
            set: { presentationDetent in
                sheetDetent = BottomSheetDetent(presentationDetent: presentationDetent)
            }
        )
    }
}
