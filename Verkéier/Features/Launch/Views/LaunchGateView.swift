import CoreSpotlight
import SwiftUI

/// Root of the app: shows the map, or the blocking route preparation screen
/// while stored transfer walks are built after a map or timetable update.
struct LaunchGateView: View {
    let locationService: LocationService
    let model: LaunchOptimisationModel

    @Environment(\.routingOptimisationService) private var optimisationService

    var body: some View {
        // The container keeps one identity, so swapping the content never restarts the task.
        Group {
            switch model.presentation() {
            case .map:
                TransitMapScreen(locationService: locationService)
                    .environment(\.launchOnboardingDidFinish, { model.onboardingDidFinish() })
            case .placeholder:
                placeholder.handlingLinks(model)
            case .optimisation(let progress):
                RoutingOptimisationScreen(state: .working(progress)).handlingLinks(model)
            case .failure:
                RoutingOptimisationScreen(state: .failed, onContinue: { model.dismissFailure() }).handlingLinks(model)
            }
        }
        .task { await model.run(using: optimisationService) }
    }

    /// The launch screen's icon on the system background.
    private var placeholder: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .overlay { Image("Icon").resizable().scaledToFit().frame(width: 200, height: 200).accessibilityHidden(true) }
    }
}

private extension View {
    /// While the map is not mounted, store incoming links for it to replay.
    func handlingLinks(_ model: LaunchOptimisationModel) -> some View {
        onOpenURL { model.forward($0) }
            .onContinueUserActivity(CSSearchableItemActionType) { model.forwardSpotlight($0) }
    }
}

#Preview("Preparing") {
    LaunchGateView(locationService: LocationService(),
                   model: LaunchOptimisationModel(initialRequirement: .needsFull, onboardingCompleted: true,
                                                  presentationDelay: .zero))
        .environment(\.routingOptimisationService, FixtureRoutingOptimisationService(stepDelay: .seconds(1)))
}
