import SwiftUI

/// The observable feature models behind the map and its sheet. The app creates
/// them once and injects each into the environment, where screens read the one
/// they need with `@Environment(StopDetailModel.self)`.
@MainActor
struct FeatureModels {
    let map: MapModel
    let stopDetail: StopDetailModel
    let lineDetail: LineDetailModel
    let tripDetail: TripDetailModel
    let routePlanner: RoutePlannerModel
    let search: SearchModel
    let favourites: FavouritesModel
    let alerts: AlertsModel

    init(routePlanner: RoutePlannerModel? = nil) {
        map = MapModel()
        stopDetail = StopDetailModel()
        lineDetail = LineDetailModel()
        tripDetail = TripDetailModel()
        self.routePlanner = routePlanner ?? RoutePlannerModel()
        search = SearchModel()
        favourites = FavouritesModel()
        alerts = AlertsModel()
    }
}

extension View {
    /// Injects every feature model into the environment.
    func featureModels(_ models: FeatureModels) -> some View {
        environment(models.map)
            .environment(models.stopDetail)
            .environment(models.lineDetail)
            .environment(models.tripDetail)
            .environment(models.routePlanner)
            .environment(models.search)
            .environment(models.favourites)
            .environment(models.alerts)
    }
}
