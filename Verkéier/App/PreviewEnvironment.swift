import SwiftUI

extension View {
    /// Injects preferences, the feature models, location and a router backed by
    /// the default unavailable services, so a screen can be previewed on its own.
    /// Configure `models` with fixture state before passing them in.
    func previewEnvironment(_ models: FeatureModels) -> some View {
        let locationService = LocationService()
        return environment(AppPreferences())
            .featureModels(models)
            .environment(locationService)
            .environment(
                SheetRouter(
                    models: models,
                    locationService: locationService,
                    routeService: MapKitRouteService(),
                    gtfsService: UnavailableGTFSService()
                )
            )
    }

    func previewEnvironment() -> some View {
        previewEnvironment(FeatureModels())
    }
}
