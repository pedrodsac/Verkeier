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
            )
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
