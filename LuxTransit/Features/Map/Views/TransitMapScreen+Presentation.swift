import AsyncAlgorithms
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

extension TransitMapScreen {
    var sheetPresentationModel: TransitSheetPresentationModel {
        let nearby = NearbyStopsPresentationModel(
            stops: viewModel.nearbyStops,
            isLoading: viewModel.isLoadingNearbyStops,
            errorMessage: viewModel.nearbyStopsErrorMessage,
            referenceLocation: locationService.currentLocation,
            routesByStopId: viewModel.nearbyStopRoutes
        )

        return TransitSheetPresentationModel(
            context: viewModel.sheetContext,
            nearby: nearby,
            commute: CommuteDashboardViewModel(
                favourites: favouriteStops,
                departuresByStopId: viewModel.favouriteDeparturesByStopId,
                isLoadingDepartures: viewModel.isLoadingFavouriteDepartures,
                errorMessage: viewModel.favouriteDeparturesErrorMessage,
                lastUpdated: viewModel.favouriteDeparturesLastUpdated,
                isStale: viewModel.areFavouriteDeparturesStale,
                expandedStopIds: viewModel.expandedFavouriteStopIds,
                nearby: nearby,
                activeAlertCount: viewModel.activeAlertCount,
                suggestedCommutePreset: viewModel.suggestedCommutePreset,
                recentStops: viewModel.recentStops
            ),
            search: SearchPresentationModel(
                results: viewModel.searchResults,
                nearbySuggestions: viewModel.nearbyStops,
                isLoadingNearbySuggestions: viewModel.isLoadingNearbyStops,
                referenceLocation: locationService.currentLocation
            ),
            stopDetail: StopDetailPresentationModel(
                stop: viewModel.selectedStop,
                routes: viewModel.selectedStopRoutes,
                departures: viewModel.filteredDepartures,
                offlineScheduledDepartures: viewModel.offlineScheduledDepartures,
                alerts: viewModel.stopDetailAlerts,
                availablePlatforms: viewModel.availableDeparturePlatforms,
                selectedLine: viewModel.selectedDepartureLine,
                selectedPlatform: viewModel.selectedDeparturePlatform,
                isLoadingDepartures: viewModel.isLoadingDepartures,
                errorMessage: viewModel.departuresErrorMessage,
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
                favouritePlaces: favouriteStops.map { RoutePlace(stop: $0, source: .favourite) },
                nearbyPlaces: viewModel.nearbyStops.map { RoutePlace(stop: $0, source: .nearby) },
                recentPlaces: viewModel.recentRoutePlaces,
                commutePresets: viewModel.commutePresets,
                recentTrips: viewModel.recentTrips,
                filters: viewModel.routeFilters,
                planningTime: viewModel.routePlanningTime,
                routeOptions: viewModel.routeOptions,
                alerts: viewModel.routeAlerts,
                legAlerts: viewModel.routeLegAlerts,
                selectedRouteOptionID: viewModel.selectedRouteOptionID,
                visibleRouteOptionCount: viewModel.visibleRouteOptionCount,
                loadingPhase: viewModel.routeLoadingPhase,
                errorMessage: viewModel.routeErrorMessage,
                statusMessage: viewModel.routeStatusMessage
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
                gtfsUpdateSnapshot: gtfsUpdateController.snapshot,
                isCheckingGTFSUpdate: gtfsUpdateController.isChecking,
                readiness: settingsReadinessSnapshot,
                supportBundleText: settingsSupportBundleText,
                debugDataMode: debugTransitDataMode
            )
        )
    }

    var settingsReadinessSnapshot: DataReadinessSnapshot {
        SettingsSupport.readinessSnapshot(
            configuration: appConfiguration,
            gtfsSnapshot: gtfsUpdateController.snapshot,
            hasBundledSeed: Bundle.main.url(forResource: "gtfs-compact", withExtension: "json") != nil
        )
    }

    var settingsSupportBundleText: String {
        SettingsSupport.supportBundleText(
            appVersion: appVersion,
            readiness: settingsReadinessSnapshot,
            gtfsSnapshot: gtfsUpdateController.snapshot,
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
                viewModel.sheetDetent.presentationDetent
            },
            set: { presentationDetent in
                viewModel.sheetDetent = BottomSheetDetent(presentationDetent: presentationDetent)
            }
        )
    }
}
