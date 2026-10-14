import SwiftUI

extension View {
    /// Injects preferences, the feature models and a router backed by the
    /// default unavailable services, so a screen can be previewed on its own.
    /// Configure `models` with fixture state before passing them in.
    func previewEnvironment(_ models: FeatureModels) -> some View {
        environment(AppPreferences())
            .featureModels(models)
            .environment(
                SheetRouter(
                    models: models,
                    locationService: LocationService(),
                    routeService: MapKitRouteService(),
                    gtfsService: UnavailableGTFSService()
                )
            )
    }

    func previewEnvironment() -> some View {
        previewEnvironment(FeatureModels())
    }
}
